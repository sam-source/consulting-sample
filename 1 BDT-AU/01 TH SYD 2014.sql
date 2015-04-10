


/*********************************************
BANGARRA 
01 Import ALL 2014 Sydney data
09/10/2014 - A Edlich

Data pulled from:
01 Bangarra_SYD optins 2014

Note SOME constituents in the QAS address file are missing.  Originals source data addresses should be used
**********************************************/

use conversion
GO

-- drop table TH_SYD_2014

create table TH_SYD_2014
(legacy_no int null,
prefix varchar(200) null,
fname varchar(30), 
lname varchar(55) null,
street1 varchar (100) null,
street2 varchar (64) null,
city varchar (30) null,
state varchar(40) null,
pcode varchar(20) null,
country varchar(40) null,
phone1 varchar(30) null,
phone2 varchar(30) null,
email varchar(150) null,
presenter_email_DNM varchar(30) null,
email_address_decline varchar(30) null,
perf_name varchar(55) null,
perf_dt varchar(30) null,
no_tix int null,
price_type varchar(30) null,
zone varchar(30) null,
location varchar(100) null,
tix_amt money null,
source_code varchar(55) null,
mos_category varchar(30) null,
order_dt varchar(30) null)

GO

BULK INSERT TH_SYD_2014
FROM '\\apramp\pub\BANG\LIVE\Data Conversion\data\01 Bangarra_SYD optins 2014.txt'
WITH
(
FIRSTROW = 2, 
MAXERRORS = 0, 
FIELDTERMINATOR = '\t',
ROWTERMINATOR = '\n'
)
GO

-- 3465

/***********************************
CASING
************************************/
/* -- run this first time
-- Sort out the field casing
CREATE FUNCTION udf_TitleCase (@InputString VARCHAR(4000) )
RETURNS VARCHAR(4000)
AS
BEGIN
DECLARE @Index INT
DECLARE @Char CHAR(1)
DECLARE @OutputString VARCHAR(255)
SET @OutputString = LOWER(@InputString)
SET @Index = 2
SET @OutputString =
STUFF(@OutputString, 1, 1,UPPER(SUBSTRING(@InputString,1,1)))
WHILE @Index <= LEN(@InputString)
BEGIN
SET @Char = SUBSTRING(@InputString, @Index, 1)
IF @Char IN (' ', ';', ':', '!', '?', ',', '.', '_', '-', '/', '&','''','(')
IF @Index + 1 <= LEN(@InputString)
BEGIN
IF @Char != ''''
OR
UPPER(SUBSTRING(@InputString, @Index + 1, 1)) != 'S'
SET @OutputString =
STUFF(@OutputString, @Index + 1, 1,UPPER(SUBSTRING(@InputString, @Index + 1, 1)))
END
SET @Index = @Index + 1
END
RETURN ISNULL(@OutputString,'')
END
*/

select * from TH_SYD_2014 

-- Update the casing on applicable fields
update QAS_EMAIL set Email = LOWER(email)
UPDATE TH_SYD_2014 set city  = dbo.udf_TitleCase(city)
UPDATE TH_SYD_2014 set street1  = dbo.udf_TitleCase(street1)
UPDATE TH_SYD_2014 set street2  = dbo.udf_TitleCase(street2)
UPDATE TH_SYD_2014 set fname  = dbo.udf_TitleCase(fname)
UPDATE TH_SYD_2014 set lname  = dbo.udf_TitleCase(lname)

UPDATE TH_SYD_2014 set fname  = dbo.udf_TitleCase(fname)
UPDATE TH_SYD_2014 set lname  = dbo.udf_TitleCase(lname)


/***********************************
ADDRESS CHECKS
***********************************/


-- TIDYING --

select * from TH_SYD_2014
-- STATE

-- fail on state not existing
select distinct a.city, a.state, a.country
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_STATE b where a.state = b.id)
and state is not null
order by a.state


update TH_SYD_2014 set state = null where state = 'London'

/*
update a
set a.city = a.state, a.state = null 
from TH_SYD_2014 a 
where ISNULL(a.city,'') = ''
and not exists (select b.description from impresario..TR_STATE b where a.state = b.id)
and a.state is not null 
*/


select distinct a.city, a.state
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_STATE b where a.state = b.id)
and state is not null
order by a.state
-- = 0


--select * from tr_state order by description

-- ensure all the states are valid for the country
select distinct a.country 
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_country b where a.country = b.description)


select distinct a.street1, a.city, a.state, a.country, a.pcode
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_state b 
								JOIN impresario..TR_COUNTRY c ON b.country = c.id 
								where a.state = b.id and a.country = c.description)
and a.country = 'Australia'


/*
update a
set a.state = 'QLD' 
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_state b 
								JOIN TR_COUNTRY c ON b.country = c.id 
								where a.state = b.id and a.country = c.description)
and a.country = 'Australia'
*/


select distinct a.city, a.state
from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_STATE b where a.state = b.id)
and state is not null
-- = 0


/***************************
PREFIX
***************************/

-- Check all the prefix's exist
select distinct a.prefix from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_PREFIX b where a.prefix = b.description)
and a.prefix is not null


update TH_SYD_2014 set prefix = 'Dr.' where prefix = 'Dr'
update TH_SYD_2014 set prefix = 'Mrs.' where prefix = 'Mrs'
update TH_SYD_2014 set prefix = 'Mr.' where prefix = 'Mr'
update TH_SYD_2014 set prefix = 'Ms.' where prefix = 'Ms'

select distinct a.prefix from TH_SYD_2014 a
where not exists (select b.description from impresario..TR_PREFIX b where a.prefix = b.description)
and a.prefix is not null
-- = 0


 
/************************************
Check field lengths
**************************************/

select * from TH_SYD_2014
where LEN(fname) > 20

select * from TH_SYD_2014
where LEN(lname) > 55

select * from TH_SYD_2014
where LEN(street1) > 64 

select * from TH_SYD_2014
where LEN(street2) > 64

select * from TH_SYD_2014
where LEN(city) > 30

select * from TH_SYD_2014 where isnull(lname,'') = ''

/****************************
ASSIGN CUSTOMER No's
*****************************/

alter table TH_SYD_2014
add customer_no int null

select distinct legacy_no, customer_no 
into #unique_no  
from TH_SYD_2014  where isnull(customer_no,'') = ''
-- = 2687

select * from impresario..t_next_id -- 45133  
where type = 'CU'
-- = 114


update impresario..t_next_id 
set next_id = 100000 + 2687 + 10
where TYPE = 'CU'  

DECLARE @counter int  
SET @counter = 100000  

UPDATE #unique_no  
SET @counter = customer_no = @counter + 1  

-- check - 
select MAX (customer_no) from #unique_no  
select * from impresario..t_next_id where type = 'CU'  

update a  
set a.customer_No = b.customer_no  
from TH_SYD_2014 a  JOIN #unique_no b ON a.legacy_no = b.legacy_no

select * from impresario..tr_original_source
--4	Converted

select * from impresario..T_DEFAULTS where field_name like ('%address%')
-- 123

-- Contact Required - NEW!
select * from impresario..T_DEFAULTS where field_name like '%contact%'

--update impresario..T_DEFAULTS set default_value = 'No' where field_name = 'REQUIRE PRIMARY CONTACT'

select * from TH_SYD_2014

-- 2687 - check the count
select distinct a.customer_no, a.prefix, a.fname, a.lname, a.street1, coalesce (b.street1, a.street1), coalesce (b.street2, a.street2), 
coalesce (b.city,a.city), coalesce (b.state, a.state), coalesce (b.pcode, a.pcode), coalesce (b.country, a.country), coalesce (b.phone1, a.phone1), coalesce (b.phone2, a.phone2), coalesce (b.email, a.email), 
4, a.legacy_no
from TH_SYD_2014 a
LEFT OUTER JOIN QAS_ADDRESS b ON a.legacy_no = b.legacy_no
LEFT OUTER JOIN QAS_EMAIL c ON a.legacy_no = c.legacy_no


-- SAME, none missing from QAS address so just nuse this
select distinct a.customer_no, a.prefix, a.fname, a.lname, a.street1, b.street1, b.street2, b.city, b.state, b.pcode, b.country, 
b.phone1, b.phone2, coalesce (b.email, a.email), 
4, a.legacy_no
from TH_SYD_2014 a
LEFT OUTER JOIN QAS_ADDRESS b ON a.legacy_no = b.legacy_no
LEFT OUTER JOIN QAS_EMAIL c ON a.legacy_no = c.legacy_no

--delete impresario..c_primary_customer where session is null

-- in QAS
insert into impresario..c_primary_customer (customer_no, prefix, fname, lname,  
street1, street2, city, state, postal_code, country, phone1, phone2, eaddress, original_source_no, ref_id)
select distinct a.customer_no, a.prefix, a.fname, a.lname, b.street1, b.street2, b.city, b.state, b.pcode, b.country, 
a.phone1, a.phone2, case when c.result in ('unreachable', 'illegitimate') then null else coalesce (c.email, a.email) END, 
4, a.legacy_no--, c.result
from TH_SYD_2014 a
JOIN QAS_ADDRESS b ON a.legacy_no = b.legacy_no
LEFT OUTER JOIN QAS_EMAIL c ON a.legacy_no = c.legacy_no
where not exists (select z.* from impresario..t_customer z where a.customer_no = z.customer_no)

-- not in QAS
insert into impresario..c_primary_customer (customer_no, prefix, fname, lname,  
street1, street2, city, state, postal_code, country, phone1, phone2, eaddress, original_source_no, ref_id)
select distinct a.customer_no, a.prefix, a.fname, a.lname, a.street1, a.street2, a.city, a.state, a.pcode, a.country, 
a.phone1, a.phone2, case when c.result in ('unreachable', 'illegitimate') then null else coalesce (c.email,a.email) END, 
4, a.legacy_no--, c.result
from TH_SYD_2014 a
LEFT OUTER JOIN QAS_EMAIL c ON a.legacy_no = c.legacy_no
where not exists (select z.* from impresario..c_primary_customer z where a.customer_no = z.customer_no and z.session is null)


select * from impresario..C_PRIMARY_CUSTOMER





/* a fix not needing to rerun
update a
set a.street1 = c.street1
from t_address a
JOIN conversion..TH_SYD_2014 b ON a.customer_no = b.customer_no
JOIN conversion..QAS_ADDRESS c ON b.legacy_no = c.legacy_no
where a.street1 <> c.street1
*/

/*
select distinct result from qas_email where result not like '%@%'
unknown
unreachable
verified
Venue/Ticket Buyer
undeliverable
illegitimate
*/

--===============================================
-- run the import
--===============================================

use impresario
go

exec cp_constituent_import_session @mode = 'R'

exec cp_constituent_import_session @mode = 'I'

-- session = 2

-- set this back
--update impresario..T_DEFAULTS set default_value = 'Yes' where field_name = 'REQUIRE PRIMARY CONTACT'


select * from tr_phone_type
-- = 5

update a
set a.address_no = null, a.type = 5
from impresario..T_PHONE a
where a.phone like ('04%') 
and type in (1,2)
and customer_no in (select customer_no from T_ADDRESS where country = 227)
and created_by = 'dbo'
and create_dt between '2014-10-21 21:00' and '2014-10-22'


-- check all the addresses are there -- all HH's? -- THESE HAVE NO ADDRESS
select a.* from T_CUSTOMER a
where not exists (select b.* from T_ADDRESS b where a.customer_no = b.customer_no)
and a.create_dt > '2014-10-21'

/*
select * from T_PHONE where customer_no in (select customer_no from #single_cust)
order by customer_no
*/

select * from t_keyword

-- in live
--select * from TX_CUST_KEYWORD where keyword_no = 5

--update T_KEYWORD set description = 'Legacy ID' where keyword_no = 5

Select * from T_KEYWORD where keyword_no = 404
-- SOH

insert into impresario..TX_CUST_KEYWORD (keyword_no, customer_no, key_value)
select distinct 404, a.customer_no, a.legacy_no
from conversion..TH_SYD_2014 a

-- PREFERENCES 
select distinct presenter_email_DNM, email_address_decline 
from conversion..TH_SYD_2014


select * from T_Customer

update a
set a.emarket_ind = 2, mail_ind = 4
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where presenter_email_DNM = 'Yes'

update a
set a.emarket_ind = 2, mail_ind = 4
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where email_address_decline = 'Do Not Email'


update a
set a.emarket_ind = 4
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull (presenter_email_DNM,'N') <> 'Yes'

update a
set a.emarket_ind = 4
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull(email_address_decline,'N') <> 'Do Not Email'

-- interests

insert into c_cust_tkw (customer_no, tkw, selected)
select distinct a.customer_no, 9, 'Y'
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull (presenter_email_DNM,'N') <> 'Yes'
UNION
select distinct a.customer_no, 9, 'Y'
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull(email_address_decline,'N') <> 'Do Not Email'

insert into c_cust_tkw (customer_no, tkw, selected)
select distinct a.customer_no, 14, 'Y'
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull (presenter_email_DNM,'N') <> 'Yes'
UNION
select distinct a.customer_no, 14, 'Y'
from T_CUSTOMER a
JOIN conversion..TH_SYD_2014 b on a.customer_no = b.customer_no
where isnull(email_address_decline,'N') <> 'Do Not Email'

-- Run the Import in REVIEW
exec CP_Constituent_Import_Session @mode = 'R'

exec CP_Constituent_Import_Session @mode = 'I'

select * from impresario..T_PHONE where create_dt > '2014-10-21'


/*************************************
IMPORT TICKET HISTORY
*************************************/
use conversion
GO

select * from TH_SYD_2014


-- Order Date
select distinct order_dt from TH_SYD_2014

select  distinct order_dt from TH_SYD_2014 where LEN(order_dt) < 9
-- = 0

select distinct order_dt from TH_SYD_2014 where LEN(order_dt) < 10

update TH_SYD_2014 set order_dt = '0' + order_dt where LEN(order_dt) = 9 and order_dt not in ('0%')

select distinct order_dt from TH_SYD_2014

select distinct order_dt from TH_SYD_2014 where LEN(order_dt) <> 10

select * from TH_SYD_2014


-- Show date
select distinct perf_dt from TH_SYD_2014

select  distinct perf_dt from TH_SYD_2014 where LEN(perf_dt) < 19


update TH_SYD_2014 set perf_dt = '0' + perf_dt where LEN(perf_dt) < 19 

select distinct perf_dt from TH_SYD_2014


-- Map the price types
select * from TH_SYD_2014
select * from impresario..tr_price_type

alter table TH_SYD_2014
add price_type_no int null

/*
-- match using the standard names
update a
set a.price_type_no = b.id
from TH_SYD_2014 a
JOIN TR_PRICE_TYPE b ON a.price_type = b.description
*/

-- one off only - in TEST

/*
create table #temp (id int identity (1,1), description varchar(30) null)
 
 insert into #temp (description)
  select distinct left(price_type,30) from TH_SYD_2014 where price_type_no is null
  
insert into [DBLIVEAE2\BANG].[impresario].[dbo].[TR_IMPORT_PRICETYPE_MATCHUP] (id, import_set, price_type, matchup_text)   
select distinct id, 1, 1, description from #temp 

*/

-- WAIT FOR MAPPING
update a
set a.price_type_no = b.price_type
from TH_SYD_2014 a
JOIN impresario..TR_IMPORT_PRICETYPE_MATCHUP b ON left(a.price_type,30) = b.matchup_text
where a.price_type_no is null 


select * from TH_SYD_2014 where price_type_no is null
-- = 0?


-- SEASON
select * from impresario..tr_season
-- ID 2 _ THIS IS ACTIVE!!!!!

/*
insert into [DBLIVEQ1\QSYM].[impresario].[dbo].[TR_SEASON] 
select * from tr_season
where id > 3
*/


-- MOS
select distinct mos_category from TH_SYD_2014

Administration -- ?
Online -- 3
Call Centre -- 4
Groups -- 4
Box Office -- 4

select * from impresario..TR_MOS
-- USING 8 - 3rd party sales

-- ZONES
select distinct zone from TH_SYD_2014

Premium
Wheelchair Companion
Wheelchair
A Reserve

alter table TH_SYD_2014
add zone_no int null

select * from impresario..t_zone

update a
set a.zone_no = b.zone_no
from TH_SYD_2014 a
JOIN impresario..T_ZONE b ON a.zone = b.description

select distinct zone, zone_no from TH_SYD_2014


select * from conversion..TH_SYD_2014

select * from impresario..t_ticket_history
--SHOULD BE THIS TOTAL
-- 88163

alter table TH_SYD_2014
add id int identity (1,1)


select * from t_ticket_history
select * from TH_SYD_2014

select MAX (tck_hist_no) from impresario..t_ticket_history
-- 72

use impresario
GO

select * from tr_mos
select * from TR_THEATER
select * from tr_season

-- #### should be 3465 rows of data ###
insert into impresario..t_ticket_history 
	(role, perf_no, 
	 perf_dt, order_dt, 
	 customer_no, mos, 
	 tck_amt, price_type, 
	 perf_name, num_seats, 
	 type, season, 
	 location, pkg_no,
	 zone_no,
	 comp_code, order_no, theater_no)
select  7, -1, 
		SUBSTRING(perf_dt,7,4) + '-' + SUBSTRING (perf_dt, 4,2) + '-' + SUBSTRING (perf_dt, 1,2) + ' ' + SUBSTRING (perf_dt, 12,8),
		SUBSTRING(order_dt,7,4) + '-' + SUBSTRING (order_dt, 4,2) + '-' + SUBSTRING (order_dt, 1,2), 
		a.customer_no, 8, 
		(no_tix * a.tix_amt), price_type_no, 
		perf_name, no_tix,
		'P',  2, --c.id,  
		location, 0, 
		zone_no, 0, 0, 4
from conversion..TH_SYD_2014 a


-- insert the constituency
select * from tr_constituency

--3 - Ticket Buyer

select * from conversion..TH_SYD_2014

select * from tx_const_cust

insert into TX_CONST_CUST (constituency, customer_no)
select distinct 3, customer_no 
from conversion..TH_SYD_2014















