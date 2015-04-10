USE [impresario]
GO
/****** Object:  StoredProcedure [dbo].[LRP_CRH_PROMOTER_SALES_RPT]    Script Date: 10/05/2012 18:53:09 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER Procedure [dbo].[LRP_CRH_PROMOTER_SALES_RPT](
	@season_str varchar(255),
	@perf_str varchar(255) = null,
	@perf_start_dt datetime = null,
	@perf_end_dt datetime = null,
	@sale_start_dt datetime,
	@sale_end_dt datetime)

AS

SET NOCOUNT ON

/***********************************************************************************************************************************
By A Edlich 08 Dec 2011 for CRH.

Sales for performances by both date range and sales to date. 

-- This doesn't support resold seats 

execute dbo.LRP_CRH_PROMOTER_SALES_RPT   
	@season_str = '80', 
	@perf_str = null, 
	@perf_start_dt = '2011-01-01', 
	@perf_end_dt = '2011-12-31', 
	@sale_start_dt = '2011-12-08', 
	@sale_end_dt = '2011-12-09'
	
execute dbo.LRP_CRH_PROMOTER_SALES_RPT   
	@season_str = '80', 
	@perf_str = '1093', 
	@perf_start_dt = null, 
	@perf_end_dt = null, 
	@sale_start_dt = '2012-01-08', 
	@sale_end_dt = '2012-09-014'

***********************************************************************************************************************************/
-- Price Categories
declare @nett int, @gst int
select @nett = 1, @gst = 3 -- gst for CRH

-- Seat Types
declare @seat_type_whc int, @seat_type_standing int
select @seat_type_whc = 8, @seat_type_standing = 3

-- Consignments
declare @consignment int
select @consignment = 5

-- Holds
declare @venue_admin int, @promoter_holds int, @venue_contract int, @production int
select @venue_admin = 1, @promoter_holds = 3, @venue_contract = 4, @production = 6

-- Sales seat status's
declare	@event_code_reserved int, @event_code_returned int, @event_code_released int, @event_code_paid int,
			@event_code_unpaid int, @event_code_new_paid int, @event_code_new_unpaid int, @event_code_new_adjust int
SELECT		@event_code_reserved = 1, @event_code_returned = 3, @event_code_released = 4, @event_code_paid = 17,
			@event_code_unpaid = 18, @event_code_new_adjust = 25, @event_code_new_paid = 26, @event_code_new_unpaid = 27
declare		@reserved_paid int, @ticketed int, @reserved int
select		@reserved_paid = 8, @ticketed = 13, @reserved = 7



-- temp table to hold all the perfs we are interested in
create table #tperf(
	perf_no int null,
	perf_dt datetime null,
	perf_code varchar(10) null,
	perf_desc varchar(30) null,
	prod_season_no int null)



-- Get the performance parameters 
-- Select using Season, & perf date range
		IF isnull(@perf_str,'0') = '0' 
			begin
				Insert	#tperf (perf_no, perf_code, perf_dt, prod_season_no, perf_desc)
				Select	a.perf_no, a.perf_code, a.perf_dt, a.prod_season_no, b.description 
				From	vs_perf a
						JOIN T_INVENTORY b (NOLOCK) ON a.perf_no = b.inv_no
						where a.perf_dt between isnull(@perf_start_dt, '1900-01-01') and isnull(@perf_end_dt, '2099-12-31')
						and charindex(',' + convert(varchar, a.season) + ',' , ',' + @season_str + ',') > 0
						
				end
-- Select using performance string		
		ELSE
				Insert	#tperf (perf_no, perf_code, perf_dt, prod_season_no, perf_desc)
				Select	a.perf_no, a.perf_code, a.perf_dt, a.prod_season_no, b.description 
				From	vs_perf a
						JOIN T_INVENTORY b (NOLOCK) ON a.perf_no = b.inv_no
						--where a.perf_no = 1093
						where charindex(',' + convert(varchar, a.season) + ',' , ',' + @season_str + ',') > 0
						and charindex(',' + convert(varchar, a.perf_no) + ',' , ',' + @perf_str + ',') > 0
						 
			

-------------------------------------------------------


Create Table #sales(
	id int identity(1,1),
	sale_ind char(2) null,
	perf_no int null,
	no_seats_sold int null,
	no_seats_reserved int null,
	no_comps int null,
	due_amt money null,
	paid_amt money null,
	price_type int null,
	zone_no int null,
	nett money null,
	gst money null)

create table #results
	(perf_no int null,
	perf_code varchar(10) null,
	perf_dt datetime null,
	perf_desc varchar (30) null,
	DR_tix_count int null,
	DR_tix_value money null,
	TD_tix_count int null,
	TD_tix_value money null,
	TD_GST_value money null,
	TD_comp_count int null,
	TD_consig_count int null,
	TD_unpaid_count int null,
	TD_holds int null,
	TD_available int null,
	TD_capacity int null,
	sales_snapshot_dt datetime null)
	
Create Clustered Index Ind_sales on #sales(perf_no)
----------------------

If @perf_str = '0'  
  Begin
	Select *
	From	#results

	Return 
  End
 

-- This gets me the Nett Price on applicable price_types 
select distinct a.perf_no, b.price_category, b.price_type, c.zone_no, c.price, b.pmap_no, b.start_dt, b.end_dt
into #price_type_deduction_nett
from #tperf a
JOIN tx_perf_pmap b (NOLOCK) ON a.perf_no = b.perf_no 
JOIN t_subprice c (NOLOCK) ON b.pmap_no = c.pmap_no 
JOIN T_PMAP d (NOLOCK) ON b.pmap_no = d.pmap_no and c.zmap_no = d.zmap_no
where b.price_category = @nett
and d.desig_code = 1


-- This gets me the GST amount on applicable price_types 
select distinct a.perf_no, b.price_category, b.price_type, c.zone_no, c.price, b.pmap_no, b.start_dt, b.end_dt
into #price_type_deduction_gst
from #tperf a
JOIN tx_perf_pmap b (NOLOCK) ON a.perf_no = b.perf_no 
JOIN t_subprice c (NOLOCK) ON b.pmap_no = c.pmap_no 
JOIN T_PMAP d (NOLOCK) ON b.pmap_no = d.pmap_no and c.zmap_no = d.zmap_no
where b.price_category = @gst
and d.desig_code = 1


-- replicate the t_order_seat_hist table to get the sli paid/returned amounts per pmap
select distinct a.order_no, a.sli_no, orig_event_date = min (a.event_date), c.price, max (a.sli_paid_amt) as sli_paid_amt
into #lt_order_seat_hist
from t_order_seat_hist a
JOIN #tperf b ON a.perf_no = b.perf_no
JOIN T_ORDER o ON a.order_no = o.order_no
JOIN #price_type_deduction_nett c ON a.perf_no = c.perf_no and a.price_type = c.price_type and o.order_dt between c.start_dt and c.end_dt
JOIN TX_PERF_SEAT p (NOLOCK) ON a.perf_no = p.perf_no and a.seat_no = p.seat_no and c.zone_no = p.zone_no
--where a.old_sli_status = 2 
--where a.order_no = 77472
where a.event_code <> 1 --
GROUP BY a.order_no, a.sli_no, c.price


--------------------------------------------------------------------------
-- Get the Sales to Date into the #sales table
--------------------------------------------------------------------------
--declare @nett int, @gst int
--select @nett = 1, @gst = 4 -- gst for CRH
--declare @seat_type_whc int, @seat_type_standing int
--select @seat_type_whc = 8, @seat_type_standing = 3
--declare @consignment int
--select @consignment = 5
--declare @venue_admin int, @promoter_holds int, @venue_contract int, @production int
--select @venue_admin = 1, @promoter_holds = 3, @venue_contract = 4, @production = 6
--declare	@event_code_reserved int, @event_code_returned int, @event_code_released int, @event_code_paid int,
--			@event_code_unpaid int, @event_code_new_paid int, @event_code_new_unpaid int, @event_code_new_adjust int
--SELECT		@event_code_reserved = 1, @event_code_returned = 3, @event_code_released = 4, @event_code_paid = 17,
--			@event_code_unpaid = 18, @event_code_new_adjust = 25, @event_code_new_paid = 26, @event_code_new_unpaid = 27
--declare		@reserved_paid int, @ticketed int, @reserved int
--select		@reserved_paid = 8, @ticketed = 13, @reserved = 7
Insert #sales(sale_ind, perf_no, no_seats_sold, no_seats_reserved, no_comps, due_amt, paid_amt, price_type, zone_no, nett, gst)
	Select	sale_ind, perf_no, sum(no_of_seats_sold), sum (no_of_seats_reserved), sum (no_comps), sum(due_amt), sum (paid_amt), price_type, zone_no, nett, gst
	From
	(
	Select	'sale_ind' = 'TD', a.perf_no, 
	case when isnull(b.due_amt,0) > 0 and a.seat_status in (@ticketed, @reserved_paid) then 1 else 0 END as no_of_seats_sold, 
	case when a.seat_status = @reserved then 1 else 0 END as no_of_seats_reserved, 
	case when isnull(b.due_amt,0) = 0 and a.seat_status in (@ticketed, @reserved_paid) then 1 else 0 end as no_comps, 
	isnull(b.due_amt,0) as due_amt, 
	isnull(b.paid_amt,0) as paid_amt, 
	b.price_type, a.zone_no, 
		isnull(s.paid_amt,0) AS nett, 
		isnull(ss.paid_amt,0) as gst
	from	tx_perf_seat a (NOLOCK) 
		JOIN #tperf p ON a.perf_no = p.perf_no
		JOIN t_sub_lineitem b (NOLOCK) ON a.sli_no = b.sli_no
		JOIN T_ORDER o (NOLOCK) ON a.order_no = o.order_no
		LEFT OUTER JOIN #price_type_deduction_nett r ON a.perf_no = r.perf_no and b.price_type = r.price_type and a.zone_no = r.zone_no and o.order_dt between r.start_dt and r.end_dt	
		LEFT OUTER JOIN #price_type_deduction_gst  y ON a.perf_no = y.perf_no and b.price_type = y.price_type and a.zone_no = y.zone_no and o.order_dt between y.start_dt and y.end_dt
		LEFT OUTER JOIN T_SLI_DETAIL s  (NOLOCK) ON a.sli_no = s.sli_no and b.sli_no = s.sli_no and s.pmap_no = r.pmap_no --and o.order_dt between r.start_dt and r.end_dt
		LEFT OUTER JOIN T_SLI_DETAIL ss (NOLOCK) ON a.sli_no = ss.sli_no and b.sli_no = ss.sli_no and ss.pmap_no = y.pmap_no --and o.order_dt between y.start_dt and y.end_dt
	where	a.perf_no in (select perf_no from #tperf)
		and a.seat_status in (@reserved_paid, @ticketed, @reserved) 
		--and b.order_no = 4451 -- testing
		) a
	group by 
		perf_no, sale_ind, price_type, zone_no, nett, gst
UNION ALL
-------------------------------------------------------------------------
-- Get the Date Range Sales (no GST data) 
-------------------------------------------------------------------------
--declare @nett int, @gst int
--select @nett = 1, @gst = 4 -- gst for CRH
--declare @seat_type_whc int, @seat_type_standing int
--select @seat_type_whc = 8, @seat_type_standing = 3
--declare @consignment int
--select @consignment = 5
--declare @venue_admin int, @promoter_holds int, @venue_contract int, @production int
--select @venue_admin = 1, @promoter_holds = 3, @venue_contract = 4, @production = 6
--declare	@event_code_reserved int, @event_code_returned int, @event_code_released int, @event_code_paid int,
--			@event_code_unpaid int, @event_code_new_paid int, @event_code_new_unpaid int, @event_code_new_adjust int
--SELECT		@event_code_reserved = 1, @event_code_returned = 3, @event_code_released = 4, @event_code_paid = 17,
--			@event_code_unpaid = 18, @event_code_new_adjust = 25, @event_code_new_paid = 26, @event_code_new_unpaid = 27
--declare		@reserved_paid int, @ticketed int, @reserved int
--select		@reserved_paid = 8, @ticketed = 13, @reserved = 7
--declare @sale_start_dt datetime, @sale_end_dt datetime
--select @sale_start_dt = '2011-12-19', @sale_end_dt = '2011-12-21'
Select	sale_ind, perf_no, sum(no_of_seats_sold), no_of_seats_reserved = 0, sum (no_comps), 0, sum(amount), price_type, zone_no, nett, gst
From(
Select 'sale_ind' = 'DR',	
	p.perf_no,
	'no_of_seats_sold' = 
		case when h.amount <> 0 then
		(SUM(IsNull(CASE 	
		WHEN 	h.event_code = @event_code_new_paid THEN 1
		WHEN 	h.event_code = @event_code_new_unpaid THEN -1
		WHEN	h.event_code = @event_code_returned THEN -1
		WHEN	h.event_code = @event_code_released and h.amount = 0 THEN -1	
		WHEN	h.event_code = @event_code_reserved and h.amount = 0 THEN 1	
		END, 0))) else 0 end,
	'no_comps' = 
		case when h.amount = 0 then
		(SUM(IsNull(CASE 	
		WHEN 	h.event_code = @event_code_new_paid THEN 1
		WHEN 	h.event_code = @event_code_new_unpaid THEN -1
		WHEN	h.event_code = @event_code_returned THEN -1
		WHEN	h.event_code = @event_code_released and h.amount = 0 THEN -1	
		WHEN	h.event_code = @event_code_reserved and h.amount = 0 THEN 1	
		END, 0))) else 0 end,
	amount = SUM(IsNull(CASE 
		WHEN h.event_code = @event_code_new_paid Then h.amount	-- full amount of the seat here
		WHEN h.event_code = @event_code_new_unpaid Then -1 * h.amount  -- negative full amount of the seat here
		WHEN h.event_code = @event_code_returned Then h.sli_paid_amt
		WHEN h.event_code = @event_code_new_adjust Then h.sli_paid_amt
		END, 0)),
		h.price_type,
		s.zone_no, 
	'nett' = SUM(IsNull(CASE 
		WHEN h.event_code = @event_code_new_paid Then coalesce (t.paid_amt,hh.price)	
		WHEN h.event_code = @event_code_new_unpaid Then -1 * coalesce (t.paid_amt, hh.price)
		WHEN h.event_code = @event_code_returned Then coalesce (t.paid_amt,hh.sli_paid_amt)
		WHEN h.event_code = @event_code_new_adjust Then coalesce (t.paid_amt, hh.price)
		END, 0)),		
		gst = 0
From t_order_seat_hist h (NOLOCK)
	LEFT OUTER JOIN #lt_order_seat_hist hh ON h.order_no = h.order_no and h.sli_no = hh.sli_no
	JOIN [dbo].t_order o (NOLOCK) ON h.order_no = o.order_no 
	JOIN #tperf p (NOLOCK) ON h.perf_no = p.perf_no
	JOIN TX_PERF_SEAT s (NOLOCK) ON h.perf_no = s.perf_no and h.seat_no = s.seat_no
	LEFT OUTER JOIN #price_type_deduction_nett r ON h.perf_no = r.perf_no and h.price_type = r.price_type and s.zone_no = r.zone_no and o.order_dt between r.start_dt and r.end_dt 
	LEFT OUTER JOIN T_SLI_DETAIL t (NOLOCK) ON t.sli_no = h.sli_no and t.pmap_no = r.pmap_no 
Where	
	(h.event_code in (@event_code_new_paid, @event_code_new_unpaid, @event_code_returned, @event_code_released, @event_code_reserved )
		)
	and h.seat_no > 0
	and h.perf_no in (select perf_no from #tperf) --> 0
	and h.event_date between isnull(@sale_start_dt,'1900-01-01') and ISNULL(@sale_end_dt,'2099-12-31')
Group By
	p.perf_no, h.price_type, s.zone_no, r.price, h.amount
) AS a
Group by perf_no, price_type, zone_no, nett, gst, sale_ind

update #sales
set nett = (nett * no_seats_sold) 
where sale_ind = 'TD'

update #sales
set gst = (gst * no_seats_sold)
where sale_ind = 'TD' 



-- Get the availables & capacity
select perf_no, COUNT (capacity) as capacity, SUM (available) as available
into #tot_seats
from (
select a.perf_no, a.seat_no as capacity, available = case when a.seat_status IN (0,3) then 1 else 0 end 
from tx_perf_seat a (NOLOCK)
JOIN T_SEAT b (NOLOCK) ON a.seat_no = b.seat_no
where perf_no in (select perf_no from #tperf)
and b.seat_type not in (@seat_type_whc, @seat_type_standing)
and a.seat_status <> 6 --blackout hold code
and a.logical_seat_num is not null
) a
GROUP BY perf_no


-- Get the Consignment & the holds
select perf_no, SUM (consignment) as consignment, SUM (holds) as holds 
into #consig_holds
from 
(select a.perf_no, case when b.type = @consignment then 1 else 0 end as 'consignment',
		case when b.type IN (@venue_admin, @promoter_holds, @venue_contract, @production) then 1 else 0 end as 'holds' 
from tx_perf_hc a (NOLOCK)
JOIN T_HC b (NOLOCK) ON a.hc_no = b.hc_no
where a.perf_no in (select perf_no from #tperf)
and b.type in (@consignment, @venue_admin, @promoter_holds, @venue_contract, @production))
as a
group by perf_no

insert into #results
select a.perf_no, a.perf_code, a.perf_dt, a.perf_desc,  
isnull(sum (case when b.sale_ind = 'DR' then b.no_seats_sold else 0 END),0), 
isnull(sum (case when b.sale_ind = 'DR' then b.nett else 0 END),0),
isnull(SUM (case when b.sale_ind = 'TD' then b.no_seats_sold else 0 END),0),
isnull (sum (case when b.sale_ind = 'TD' then b.nett else 0 END),0),
isnull (sum (case when b.sale_ind = 'TD' then b.gst else 0 END),0),
isnull (sum (case when b.sale_ind = 'TD' then no_comps else 0 END),0),
isnull(c.consignment,0),  isnull(sum (case when b.sale_ind = 'TD' then no_seats_reserved else 0 END),0), isnull (c.holds,0),
isnull(d.available,0), isnull(d.capacity,0), case when CONVERT(VARCHAR(10), @sale_end_dt, 120) >= CONVERT(VARCHAR(10), GETDATE(), 120)
then GETDATE() else @sale_end_dt END
from #tperf a
LEFT OUTER JOIN #sales b ON a.perf_no = b.perf_no
LEFT OUTER JOIN #consig_holds c ON a.perf_no = c.perf_no
LEFT OUTER JOIN #tot_seats d ON a.perf_no = d.perf_no
group by a.perf_no, a.perf_desc, a.perf_dt, a.perf_desc, a.perf_code, c.consignment, c.holds, d.available, d.capacity

select * from #results





