USE [impresario]
GO
/****** Object:  StoredProcedure [dbo].[LWP_VALIDATE_CART]    Script Date: 07/24/2014 12:23:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO

ALTER Proc [dbo].[LWP_VALIDATE_CART]
    (	@SessionKey varchar(64) = null	
       ,@Validate_Point int     = null
       ,@PerfNoSel varchar (500) = '' )
    with execute as 'dbo'
AS
/*************************************************************************
 
 Created by Roger Boltz -- 01/12/2011
 ~~~~~~~~~~~~~~~~~~~~~~ 
 
 This proc can be  called from the web API using the method validateCustomOffer.
 @SessionKey indicates the web session_id which can be used to identify the 
 web order for which the proc is called. @Validate_Point tells the proc WHY
 it has been called (at what point in the purchase path.)
 
 @PageText is the text and/or HTML code returned to the API call which will
 be inserted into the next web page displayed to the web user. This may be a
 simple message, or may contain HTML tags and images, or it may use javascript
 to define a button, radio buttons, a dropdown list or check boxes which
 when clicked will return to this proc for further processing by making the 
 HREF="../precart/precart.asmx?p=1005405001" where 1005405001 indicates the 
 particular button being clicked including an integer value that may be the
 encryption of the results of the control.
 
 This procedure uses a logic structure that may look familiar to moldy old
 programmers of 3rd generation languages like BASIC, COBOL and FORTRAN.  For
 IF/THEN logic used in SQL. It avoids duplication of code and deeply nested
 IF statements, and it is very easy to follow, modify and troubleshoot once
 you get used to its flow. It is also more efficient: speed is essential here.
 
 There is ONE entry point and ONE exit point for each module, so that logic 
 can be added after each exit point determining  where to go next.  To 
 use a SUB-MODULE of one of the main modules, GoTo the MAIN module and let
 IT check the @validate_point to decide where to go from there.
 -----------------------------------------------------------------------
 
 Adapted for Melbourn Festival by RAB - 12 July 2012
 
 
************************************************************************/
Set NoCount On

--#######
--RETURN -- IN CASE OF EMERGENCY, BREAK GLASS
--#######

/************************************************************************
 Validaton Points, Button Click Definitions & Site Specific Values
************************************************************************/
declare -- Validation Points
        @Single_Added       int
       ,@Aux_Sng_Added      int
       ,@Subscript_Added    int
       ,@Aux_Sub_Added      int
       ,@Renewal_Added      int
       ,@Aux_Ren_Added      int
       ,@Cont_Added         int
       ,@Cart_Action        int
       ,@Cart_Deletion      int
       ,@Checkout           int
       ,@Login              int
       -- Buttons
       ,@Discount_Mode      int
       ,@Matinee_Mode       int
       ,@Add_Cont_BTN       int
       ,@Pre_Selected_Perfs	int
       
                                             -----------------------------
select  @Single_Added     =  1 --     <---<<< Set site-specific values here
       ,@Aux_Sng_Added    =  2                -----------------------------
       ,@Subscript_Added  =  3
       ,@Aux_Sub_Added    =  4
       ,@Renewal_Added    =  5
       ,@Aux_Ren_Added    =  6
       ,@Cont_Added       =  7
       ,@Cart_Deletion    =  8
       ,@Checkout         =  9
       ,@Login            = 10
       ,@Discount_Mode    = 901
       ,@Add_Cont_BTN	  = 1900000000
       ,@Pre_Selected_Perfs = 100
              

-----------------------------------------
-- Set values for TNEWSqlBridge CLR calls
-----------------------------------------
declare @N_API_URL	    Nvarchar(500)
       ,@N_session_key	Nvarchar(128)

set @N_session_key =cast(@sessionkey as Nvarchar(128))

if  (select default_value from T_DEFAULTS where field_name='title bar text') like '%test%'
  or charindex('test', @@servername)>0
    set @N_API_URL=N'http://mfeslb/TESTapi/tessitura.asmx'
else 
    set @N_API_URL=N'http://mfeslb/LIVEapi/tessitura.asmx'
       
---------------------------------
-- Create custom tables as needed
---------------------------------
--drop table LTR_TNEWCustom_Content_Type
if not exists (select * from sysobjects where name='LTR_TNEWCustom_Content_Type')
    BEGIN
    create table LTR_TNEWCustom_Content_Type
        ( id                int primary key identity
         ,Content_Type      varchar(30)
         ,Description       varchar(100) )
    grant select, insert, update, delete on LTR_TNEWCustom_Content_Type to impusers
    exec lp_configure_ref_table_v11 'LTR_TNEWCustom_Content_Type'
    END
    

-- drop table LTR_TNEWCustom_Content
-- delete from tr_reference_table where table_name='LTR_TNEWCustom_Content'
-- delete from tr_reference_column where reference_table_id=(select id from TR_reference_table where table_name = 'LTR_TNEWCustom_Content')
if not exists (select * from sysobjects where name='LTR_TNEWCustom_Content')
    BEGIN
    create table LTR_TNEWCustom_Content
        ( id                int primary key identity
         ,Content_Type      varchar(30)
         ,MOS               int
         ,Constituency      int
         ,Price_Type_Group  int
         ,Value				int
         ,From_Dt           datetime
         ,Thru_Dt           datetime
         ,Button_TEXT       varchar(20)
         ,Short_TEXT        varchar(50)
         ,Long_TEXT         varchar(4000) )
    grant select, insert, update, delete on LTR_TNEWCustom_Content to impusers
    exec lp_configure_ref_table_v11 'LTR_TNEWCustom_Content'
    END

--Create table for Session Variables so they transcend log-in
if not exists (select * from sysobjects where name='lt_web_session_variable')
    CREATE TABLE [dbo].[lt_web_session_Variable](
	    [SessionKey] [varchar](64) NOT NULL,
	    [Name] [varchar](100) NOT NULL,
	    [Value] [varchar](1000) NOT NULL,
     CONSTRAINT [PK_LT_WEB_SESSION_VARIABLE] PRIMARY KEY CLUSTERED 
        ([SessionKey] ASC,	[Name] ASC)
      WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, 
            IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, 
            ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]) ON [PRIMARY]

--drop table lt_web_changed_prices
if not exists (select * from sysobjects where name='lt_web_changed_prices')
    BEGIN
    create table lt_web_changed_prices
        ( sessionkey        varchar(64)
         ,sli_no            int
         ,orig_pricetype    int )
    grant select, insert, update, delete on lt_web_changed_prices to impusers
    END
    
-- Local reference table to configure what to check and what to display
-- drop table LTR_TNEWCustom_Disc_Message
-- delete from tr_reference_table where table_name='LTR_TNEWCustom_Disc_Message'
-- delete from tr_reference_column where reference_table_id=(select id from TR_reference_table where table_name = 'LTR_TNEWCustom_Disc_Message')
IF NOT EXISTS ( SELECT  *
                FROM    sysobjects
                WHERE   name = 'LTR_TNEWCustom_Disc_Message' ) 
    BEGIN
        CREATE TABLE LTR_TNEWCustom_Disc_Message
            (
             id INT PRIMARY KEY IDENTITY
            ,Keyword INT
            ,Num_Perfs_Kwd INT
            ,Num_Perfs_Total INT
            ,Message_Text VARCHAR(4000)
            ,Disable_Checkout CHAR(1)
            )
        GRANT SELECT, INSERT, UPDATE, DELETE ON LTR_TNEWCustom_Disc_Message TO impusers
        EXEC lp_configure_ref_table_v11 'LTR_TNEWCustom_Disc_Message'
    END
   
-- Local table  and internal variable to track Pre Selected perfs from external path
if not exists(select * from sysobjects where name='lt_preselected_perfs')
    BEGIN
    create table lt_preselected_perfs
        ( sessionkey    varchar(800)
         ,pd_no			int
         ,pds_no		int
         ,perf_no       int
         ,pds_desc		varchar(55)
         ,perf_dt		datetime null
         ,processed     char(1)     )
    grant select, insert, update, delete on lt_preselected_perfs  to impusers
    END


/************************************************************************
 HOUSEKEEPING - Declarations and Initializations
************************************************************************/
Declare -- Try to keep in alphabetical order
     @back_btn	        varchar(2000)
    ,@BTN_Parm1	        varchar(10)
    ,@BTN_Parm2	        varchar(10)
    ,@BTN_Parm3	        varchar(10)
    ,@button	        varchar(1000)
    ,@buy_perf_desc	    varchar(30)
    ,@buy_perf_no	    int
    ,@buy_price_desc	varchar(30)
    ,@buy_price_str	    varchar(100)
    ,@buy_pricetype	    int
    ,@buy_seats	        float
    ,@cart_btn	        varchar(2000)
    ,@cart_count	    int
    ,@cart_perfs	    int
    ,@cart_seats	    int
    ,@cart_total	    money
    ,@checkout_btn	    varchar(2000)
    ,@choice_text	    varchar(100)
    ,@CMD	            varchar(4000)
    ,@const_pricetype	int
    ,@constituency	    int
    ,@cont_amt	        money
    ,@CSI	            varchar(4000)
    ,@custom_btn_txt    varchar(20)
    ,@custom_msg_1      varchar(50)
    ,@custom_msg_2      varchar(4000)
    ,@customer_no	    int
    ,@discount_desc	    varchar(30)
    ,@discount_no	    int
    ,@dlr_disc	        money
    ,@end_dt	        datetime
    ,@fee_amt	        money
    ,@fee_id	        int
    ,@fee_no	        int
    ,@fund_no	        int
    ,@get_perf_desc	    varchar(30)
    ,@get_perf_no	    int
    ,@get_price_desc	varchar(30)
    ,@get_pricetype	    int
    ,@get_seats	        float
    ,@id	            int
    ,@idx	            int
    ,@li_no	            int
    ,@li_seq_no	        int
    ,@login_btn	        varchar(2000)
    ,@m_seat_nos	    varchar(1000)
    ,@max_seats	        int
    ,@min_perfs	        int
    ,@min_seats	        int
    ,@mos	            int
    ,@msg_end	        varchar(100)
    ,@msg_header	    varchar(1000)
    ,@N_API_CSINote	    Nvarchar(4000)
    ,@N_price_type	    Nvarchar(50)
    ,@new_mos	        int
    ,@new_price	        money
    ,@new_pricetype     int
    ,@num_perfs	        int
    ,@num_seats	        int
    ,@offer_text	    varchar(5000)
    ,@OK	            int
    ,@old_price	        money
    ,@order_no	        int
    ,@orig_MOS	        int
    ,@PageText	        varchar(4000)
    ,@pct_disc	        int
    ,@perf_count	    int
    ,@perf_desc	        varchar(60)
    ,@perf_dt	        datetime
    ,@perf_no	        int
    ,@perf_save	        int
    ,@perf_seats	    int
    ,@pkg_code	        varchar(10)
    ,@pkg_no	        int
    ,@precart_btn	    varchar(2000)
    ,@price_type	    int
    ,@ref_no	        int
    ,@req_seats	        float
    ,@row	            varchar(10)
    ,@season	        int
    ,@season_desc	    varchar(60)
    ,@seat_desc	        varchar(30)
    ,@seat_no	        int
    ,@seat_num	        varchar(10)
    ,@seats	            int
    ,@section	        varchar(30)
    ,@sli_no            int
    ,@source_no	        int
    ,@SQL	            varchar(4000)
    ,@today	            datetime
    ,@User_Logged_In	char(1)
    ,@zone_no	        int
    ---------------------------------
    ,@cst_btn_label     varchar(30)
    ,@cst_btn_text      varchar(55)
    ,@cst_btn_label2    varchar(30)
    ,@cst_btn_text2     varchar(55)
    ,@cst_page_msg      varchar(4000)
    ,@month             int
    ,@year              INT
    ,@total_perfs		INT
    ,@total_kwd_perfs	INT
    ,@disable_checkout	CHAR(1)
    ,@rules_mos			INT
    ,@matinee_mos		INT
    ,@less_than3_PTG	INT
    ,@3_or_more_PTG		INT
    ,@3_or_more_MOS		INT
    ,@amt_1             money
    ,@amt_2             money
    ,@level             int
    ,@ga_header			varchar(4000)
    ,@ga_up_btn_text    varchar(200)
    ,@ga_up_btn		    varchar(30)
    ,@ga_other_btn_text varchar(200)
    ,@ga_other_btn		varchar(30)
    ,@ga_footer			varchar(4000)
    ,@ga_no_btn_text    varchar(200)
    ,@ga_no_btn		    varchar(30)
    ,@account_fund		int
    ,@same_perf         int
    ,@imgURL            varchar(1000)
    ,@img_source        varchar(500)
    ,@prod_synopsis     varchar(4000)
    ,@pds_no            int
    ,@pds_desc          varchar(55)
    ,@Local_Proc_ID     int
    ,@pd_no				int
    ,@prod_short_desc varchar(4000)
    ,@buy_perf_dt		varchar(60)
    ,@orig_mos_order	int 
    
-- Define HTML for displays and controls
set @button='<input type="button" class="btnStyle" '
--  +'STYLE=" 
--          +color: #000;' --#fff;'
--          +'padding: 2px 5px;'
--          --+'border: 4px solid;'
--          --+'border-color: #f00 #900 #900 #f00;' --(RED)
--          --+'background-color:#c00;'             --(RED
--          --+'border-color: #7bf #07c #07c #7bf;' --(BLUE)
--          --+'background-color: #09f;'            --(BLUE)
--          +'font-family: Georgia, ..., serif;'
--          +'font-size: 14px;'
--          +'display: inline;'
----          +'height: 30px;'
----          +'width: 250px;'
--          +'" ' --/>''

set @back_btn=@button
   --+'VALUE="   BACK   " onClick="history.go(-1);return true;">'
   +'VALUE="   BACK   " onClick="history.back();return false;">'

set @login_btn=@button
   +'VALUE="  LOG IN  " onClick="location.href=''../account/login.aspx'';">'

set @cart_btn=@button
   +'value="GO TO CART" onclick="location.href=''../cart/cart.aspx'';">'

set @precart_btn=@button
   +'value="Continue"   onclick="location.href=''../cart/precart.aspx?p=1''; "/> '

set @checkout_btn=@button
   +'value=" CHECKOUT " onclick="location.href=''../checkout/checkout.aspx'';">'


set @msg_header
    --='<font size="2"><font color="#E31B23">' -- RED
    --='<font size="2"><font color="#FFFFFF">' -- WHITE
    ='<title>Melbourne Festival</title>' +'<font size="4"><font color="#6F6F6F">' -- BLACK
set @msg_end='<font size="1"><font color="#6F6F6F">'    -- BLACK
set @today = getdate()


/**********************************************************************
 GET SESSION & CURRENT ITEM INFO
**********************************************************************/
-- Get local proc ID for this procedure (so we can create a URL to call it)
    select @Local_Proc_ID=id from TR_LOCAL_PROCEDURE where procedure_name='LWP_VALIDATE_CART'

-- Get order info
    select @customer_no=isnull(a.customer_no,0)
          ,@order_no   =isnull(a.order_no,0)
          ,@source_no  =isnull(a.source_no,0)
          ,@mos        =isnull(b.mos,0)
          ,@orig_mos_order=ISNULL(b.originalmos,0)
      from t_web_order a
      JOIN t_web_session_Session b (NOLOCK) ON a.sessionkey = b.SessionKey
     where a.sessionkey=@sessionkey

-- Is user logged-in?
    if (select value from t_web_session_Variable where SessionKey=@sessionkey and name='UserName')
      =(select top 1 Default_Login from LTR_TN_EXPRESS_WEB_DEFAULTS)
      set @User_Logged_In='N'
    else
      set @User_Logged_In='Y'

-- Find target lineitem (most recent lineitem in current order)
    select @li_seq_no =MAX(isnull(li_seq_no,0))
      from T_WEB_SUB_LINEITEM
     where order_no=@order_no
     
-- Get perf_no, pricetype, etc.
    select @perf_no=max(perf_no)
          ,@pkg_no=max(pkg_no)
          ,@price_type=max(price_type)
          ,@seats=count(1)
      from T_WEB_SUB_LINEITEM sli
     where li_seq_no=@li_seq_no

--#####################################################################
--  SWITCHBOARD:       GO TO REQUESTED BUTTON OR VALIDATION POINT
--#####################################################################

--------------------------------------------------------------
-- PRE PROCESSING FOR ALL VALIDATION POINTS
--------------------------------------------------------------
    if @Validate_Point < 20 -- Set appropriate logic
        GoTo PRE_VALIDATION
        
---------------------------
RETURN_From_PRE_VALIDATION:
---------------------------

  --------------------------------------------------------------

    -- TNEW Defined Validation Points
    if @Validate_Point = @Single_Added      GoTo SINGLE_ADDED
    if @Validate_Point = @Aux_Sng_Added     GoTo AUX_SNG_ADDED
    if @Validate_Point = @Subscript_Added   GoTo SUBSCRIPT_ADDED
    if @Validate_Point = @Aux_Sub_Added     GoTo AUX_SUB_ADDED
    if @Validate_Point = @Renewal_Added     GoTo RENEWAL_ADDED
    if @Validate_Point = @Aux_Ren_Added     GoTo AUX_REN_ADDED
    if @Validate_Point = @Cont_Added        GoTo CONT_ADDED
    if @Validate_Point = @Cart_Deletion     GoTo CART_DELETION
    if @Validate_Point = @Login             GoTo CUST_LOGIN
    if @Validate_Point = @Checkout          GoTo CHECKOUT

    -- Button Clicks Defined in modules below (Rename if used)
    if @Validate_Point between @Discount_Mode
                           and @Discount_Mode + 999999999
                                            GoTo Discount_Mode
                                            
    IF @Validate_Point BETWEEN @Add_Cont_BTN
                           AND @add_cont_BTN + 99999999
                                            GoTo Add_Cnt_BTN        -- 1900000000
	if @Validate_Point = @Pre_Selected_Perfs    GoTo PRE_SELECTED_PERFS     -- 100
                                            
    GoTo RETURN_TO_WEB -- Must'a left someth'n out...?

--#####################################################################


/**********************************************************************
                     PRE VALIDATION PROCESSING
**********************************************************************/
-----------------------------------------------------------------------
PRE_VALIDATION: -- This gets done first regardless of the VP specified
-----------------------------------------------------------------------
SET @rules_mos = ISNULL((SELECT MOS FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Rules_MOS'),0)
SET @matinee_mos = ISNULL((SELECT MOS FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Matinee_MOS'), 0)
SET @3_or_more_MOS =  (SELECT MOS FROM LTR_TNEWCustom_Content WHERE Content_Type = '3_or_more_PTG')
------------------
--Package Discount
------------------
    if @mos NOT IN(@rules_mos, @3_or_more_MOS) 
        GoTo End_Pkg_Dsc

    if @orig_mos_order = @matinee_mos
		GoTo Matinee_Dsc
        
Pkg_dsc:
 
SET @less_than3_PTG = (SELECT Price_Type_Group FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Less_than3_PTG')
SET @3_or_more_PTG =  (SELECT Price_Type_Group FROM LTR_TNEWCustom_Content WHERE Content_Type = '3_or_more_PTG')
SET @orig_MOS = (SELECT CAST(Value AS INT) FROM t_web_session_Variable where SessionKey=@sessionkey and Name='MOS_Changed_From') 
SET	@total_perfs = (SELECT COUNT(DISTINCT wli.perf_no) FROM T_WEB_LINEITEM wli WHERE wli.order_no = @order_no)
					
SELECT @total_kwd_perfs = COUNT(DISTINCT wli.perf_no) 
	FROM T_WEB_LINEITEM wli 
		JOIN T_PERF prf on wli.perf_no = prf.perf_no
		JOIN dbo.TX_INV_TKW tit ON prf.prod_season_no = tit.inv_no
		WHERE wli.order_no = @order_no
			AND tit.tkw IN (SELECT keyword FROM LTR_TNEWCustom_Disc_Message WHERE inactive <>'Y')

    --3rd Show PT Change
    if @total_perfs >= 3
        BEGIN
			if ISNULL(@3_or_more_MOS, @mos) <> @mos 
			 and not exists(select * from t_web_session_Variable where SessionKey=@sessionkey and Name='MOS_Changed_From')
                BEGIN
					exec lwp_CLR_ChangeModeOfSaleEx
						@ApiURL         = @N_API_URL
					   ,@sessionkey     = @N_session_key
					   ,@NewModeOfSale  = @3_or_more_MOS 
	                
					select @mos=mos from T_WEB_ORDER where sessionkey=@sessionkey
					insert t_web_session_Variable values(@sessionkey, 'MOS_Changed_From', cast(@mos as varchar))
                END
                
			declare sli_cur insensitive cursor for
			 select sli.sli_no, sli.price_type, sli.perf_no
			 from T_WEB_SUB_LINEITEM   sli
			 join TR_PRICE_TYPE        ptp on ptp.id=sli.price_type
			where sli.order_no=@order_no
			 and ptp.price_type_group in (@3_or_more_PTG, @less_than3_PTG)
	          
			open sli_cur
			fetch sli_cur into @sli_no, @buy_pricetype, @buy_perf_no
			while @@fetch_status=0
				BEGIN
					select @new_pricetype=
							MIN(price_type)
					  from TX_PERF_PMAP     ppm
					  join TR_PRICE_TYPE    ptp on ptp.id=ppm.price_type
					 where perf_no= @buy_perf_no
					   and ptp.price_type_group = ISNULL(@3_or_more_PTG, @buy_pricetype) -- 3+ Performances
					   and GETDATE() between ppm.start_dt and ppm.end_dt
		 
					if @buy_pricetype<>@new_pricetype
						BEGIN
							exec lwp_CLR_UpdatePriceType
								@ApiUrl             = @N_API_URL
							   ,@SessionKey         = @N_session_key
							   ,@LineItemNumber     = 0
							   ,@SubLineItemNubmer  = @sli_no
							   ,@oldprice           = 0
							   ,@NewPrice           = @new_pricetype
			            
							if not exists(select * from lt_web_changed_prices
										   where sessionkey=@sessionkey and sli_no=@sli_no)
								insert lt_web_changed_prices values(@sessionkey, @sli_no, @buy_pricetype)
						END   
					fetch sli_cur into @sli_no, @buy_pricetype, @buy_perf_no
				END
			deallocate sli_cur
        END
	ELSE --< 3 show PT change
		BEGIN
			declare sli_cur insensitive cursor for
			 select sli.sli_no, sli.price_type, sli.perf_no
			 from T_WEB_SUB_LINEITEM   sli
			 join TR_PRICE_TYPE        ptp on ptp.id=sli.price_type
			where sli.order_no= @order_no
			 and ptp.price_type_group in(@3_or_more_PTG, @less_than3_PTG)
	          
			open sli_cur
			fetch sli_cur into @sli_no, @buy_pricetype, @buy_perf_no
			while @@fetch_status=0
				BEGIN
					select @new_pricetype=price_type
					  from TX_PERF_PMAP     ppm
					  join TR_PRICE_TYPE    ptp on ptp.id=ppm.price_type
					 where perf_no=@buy_perf_no
					   and ptp.price_type_group=ISNULL(@less_than3_PTG, @buy_pricetype)-- <3 perfs
					   and GETDATE() between ppm.start_dt and ppm.end_dt
		 
					if @buy_pricetype<>@new_pricetype
						BEGIN
							exec lwp_CLR_UpdatePriceType
								@ApiUrl             = @N_API_URL
							   ,@SessionKey         = @N_session_key
							   ,@LineItemNumber     = 0
							   ,@SubLineItemNubmer  = @sli_no
							   ,@oldprice           = 0
							   ,@NewPrice           = @new_pricetype
			            
							if not exists(select * from lt_web_changed_prices
										   where sessionkey=@sessionkey and sli_no=@sli_no)
								insert lt_web_changed_prices values(@sessionkey, @sli_no, @buy_pricetype)
						END   
					fetch sli_cur into @sli_no, @buy_pricetype, @buy_perf_no
				END
			deallocate sli_cur
			if ISNULL(@3_or_more_MOS, 0) = @mos
			 and exists(select * from t_web_session_Variable where SessionKey=@sessionkey and Name='MOS_Changed_From')
                BEGIN
					exec lwp_CLR_ChangeModeOfSaleEx
						@ApiURL         = @N_API_URL
					   ,@sessionkey     = @N_session_key
					   ,@NewModeOfSale  = @orig_MOS 
	                
					select @mos=mos from T_WEB_ORDER where sessionkey=@sessionkey
					
                END
        END

------------
End_Pkg_Dsc:
------------

--------------------------------------------
--Matinee Discount
--------------------------------------------

Matinee_Dsc:

    if @mos NOT IN(@matinee_mos) 
		and @orig_mos_order not in (@matinee_mos)
        GoTo End_Mat_Dsc
       
SET @less_than3_PTG = (SELECT Price_Type_Group FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Less_than3_PTG')
SET @3_or_more_PTG =  (SELECT Price_Type_Group FROM LTR_TNEWCustom_Content WHERE Content_Type = '3_or_more_PTG')
SET @orig_MOS = (SELECT CAST(Value AS INT) FROM t_web_session_Variable where SessionKey=@sessionkey and Name='MOS_Changed_From') 
SET	@total_perfs = (SELECT COUNT(DISTINCT wli.perf_no) FROM T_WEB_LINEITEM wli WHERE wli.order_no = @order_no)

    --3rd Show PT Change
    if 	@orig_MOS_order = @matinee_mos and @mos <> @matinee_mos
        BEGIN
			if not exists(select * from t_web_session_Variable where SessionKey=@sessionkey and Name='MOS_Changed_From')
                BEGIN
					exec lwp_CLR_ChangeModeOfSaleEx
						@ApiURL         = @N_API_URL
					   ,@sessionkey     = @N_session_key
					   ,@NewModeOfSale  = @matinee_MOS 
	                
					select @mos=mos from T_WEB_ORDER where sessionkey=@sessionkey
					insert t_web_session_Variable values(@sessionkey, 'MOS_Changed_From', cast(@mos as varchar))
                END
       END

------------
End_Mat_Dsc:
------------
   
------------
End_Pre_Val:
------------
    GoTo RETURN_From_PRE_VALIDATION

/**********************************************************************
                         MODULES FOR BUTTONS
**********************************************************************/
------------------------------------------------------------------------------
PRE_SELECTED_PERFS: -- URL of prod seasons and perfs to display on precart page
------------------------------------------------------------------------------
if not exists (select * from LTR_TNEWCustom_Content where Content_Type = 'Pre_Selected_Perfs' and ISNULL (inactive,'N') = 'N')
GoTo End_PRE_SELECTED_PERFS

    if exists(select * from lt_web_session_variable 
                      where sessionkey=@sessionkey
                        and name='PreSelected_Perfs_Loop'
                        and value='Active')
        GoTo Display_PRE_SELECTED_PERFS


-- This splits out the string of comma separated values
declare @sel_values table (value int)

WHILE CHARINDEX(',', @PerfNoSel) > 0 
BEGIN
    DECLARE @tmpstr VARCHAR(50)
     SET @tmpstr = SUBSTRING(@PerfNoSel, 1, ( CHARINDEX(',', @PerfNoSel) - 1 ))

    INSERT  INTO @sel_values (Value)
    VALUES  ( @tmpstr)          
    SET @PerfNoSel = SUBSTRING(@PerfNoSel, CHARINDEX(',', @PerfNoSel) + 1, LEN(@PerfNoSel))
END


       insert into lt_preselected_perfs
         select distinct 
				@SessionKey
               ,s.prod_no
               ,p.prod_season_no
               ,p.perf_no
               ,inv.description
               ,p.perf_dt
               ,'N'
           from @sel_values o	
           JOIN T_PERF p (NOLOCK) ON ltrim(rtrim(o.value)) = p.perf_no
           JOIN T_PROD_SEASON s (NOLOCK) ON p.prod_season_no = s.prod_season_no
           join t_inventory     inv (NOLOCK) on inv.inv_no=p.perf_no
           where not exists (select 1
                          from T_WEB_LINEITEM ltm
                          join t_perf         prf on p.perf_no=ltm.perf_no
                          join T_PROD_SEASON pd ON prf.prod_season_no = pd.prod_season_no
                          where ltm.order_no = @order_no
                          and ltm.perf_no=p.perf_no 
                          and prf.prod_season_no=o.value)
           	UNION
			 select distinct  
				@SessionKey
               ,s.prod_no
               ,p.prod_season_no
               ,perf_no = null
               ,inv.description
               ,''
               ,'N'
           from @sel_values o	
           JOIN T_PERF p (NOLOCK) ON ltrim(rtrim(o.value)) = p.prod_season_no
           JOIN T_PROD_SEASON s (NOLOCK) ON p.prod_season_no = s.prod_season_no
           join t_inventory     inv (NOLOCK) on inv.inv_no=p.prod_season_no
           where not exists (select 1
                          from T_WEB_LINEITEM ltm
                          join t_perf         prf on p.perf_no=ltm.perf_no
                          join T_PROD_SEASON pd ON prf.prod_season_no = pd.prod_season_no
                         where ltm.order_no = @order_no
                          and ltm.perf_no=p.perf_no
                          and prf.prod_season_no=o.value)
             
             
		if @@rowcount=0
		GoTo End_PRE_SELECTED_PERFS
		
		if exists (select * from lt_web_session_Variable where SessionKey = @SessionKey and Name = 'PreSelected_Perfs_Loop')
		GoTo Display_PRE_SELECTED_PERFS
		         
    else 
    
        insert lt_web_session_variable (sessionkey, name, value)
            values(@sessionkey, 'PreSelected_Perfs_Loop','ACTIVE')

--------------------------
Display_PRE_SELECTED_PERFS:
--------------------------

     update a
     set a.processed = 'Y'
     from lt_preselected_perfs a
     join t_web_order w ON a.sessionkey = w.sessionkey
     JOIN t_web_lineitem o ON w.order_no = o.order_no
     LEFT OUTER join T_PERF b ON a.perf_no = b.perf_no
     LEFT OUTER JOIN T_PERF c ON a.pds_no = c.prod_season_no
     where o.perf_no = coalesce (b.perf_no,c.perf_no)
     and a.sessionkey = @SessionKey 

    -- Get custom values for page heading, button label and button text
    select @cst_btn_label=Button_TEXT
        ,@cst_page_msg=Long_TEXT
        ,@cst_btn_text=Short_TEXT
    from LTR_TNEWCustom_Content
    where isnull(inactive,'N')<>'Y'
    and coalesce(mos,@mos,0)=coalesce(@mos,0)
    and GETDATE() between ISNULL(From_Dt,'1/1/2000') and DATEADD(HOUR,23,isnull(Thru_Dt,'12/31/2100'))
    and Content_Type='Pre_Selected_Perfs'

    -- Provide defaults if values not found above
    select @cst_btn_label=coalesce(@cst_btn_label, '  Select  ')
      ,@cst_page_msg =coalesce(@cst_page_msg, 'Please make your ticket selection below.')
      ,@cst_btn_text=coalesce(@cst_btn_text, 'I don''t wish to make any further selections.') 


    -- Place header on page -- need to do it as a conditional statement, otherwise it comes back to here with just the page header when no items are left 
    if not exists (select top 1 * from lt_preselected_perfs where sessionKey = @sessionkey 
					and processed = 'N') 
    GoTo End_PRE_SELECTED_PERFS
    
    else
  
 if @PageText is null
    set @PageText=--@PageText
    --+
    @cst_page_msg+'<br><br>'
   

   declare pds_cur insensitive cursor for
     select adn.perf_no
           ,adn.pds_no
           ,adn.pds_desc
           ,adn.pd_no
           ,cast(DATENAME(dw, adn.perf_dt) as varchar) + ', ' + CAST(DAY(adn.perf_dt) AS VARCHAR(2)) + ' ' + cast(DATENAME(MM, adn.perf_dt) as varchar) 
														+ ', ' + cast(DATENAME(YYYY, adn.perf_dt) as varchar)
														+ '' + cast(stuff( lower(right( convert( varchar(26), adn.perf_dt, 109 ), 15 )), 7, 7, '' ) as varchar) 
       from lt_preselected_perfs adn
      where sessionkey=@SessionKey
        and processed='N'
        and not exists (select ltm.*
                          from T_WEB_LINEITEM ltm
                          left outer join t_perf         prf on prf.perf_no=ltm.perf_no 
                          left outer join t_perf         pds on pds.perf_no=ltm.perf_no 
                         where ltm.order_no = isnull(@order_no,0)
							and isnull(adn.perf_no,0) = coalesce (prf.perf_no,pds.perf_no)
							and prf.prod_season_no=adn.pds_no)
    open pds_cur
    if @@cursor_rows=0
        GoTo FINISHED_PRESELECTION_BTN
 
    fetch pds_cur into @buy_perf_no, @pds_no, @pds_desc, @pd_no, @buy_perf_dt 

 if @PageText is not null
     set @PageText=@PageText
   
        
    while @@FETCH_STATUS=0
        BEGIN
        -- Get image for performance if available
        set @img_source=null
        
        -- MFES specific
        
         select @img_source=
				value -- Try to get image for Prod-Season
          from tx_inv_content
         where inv_no=@pds_no
           and content_type=9 -- Prod Image
        
        if @img_source is null   
        select @img_source=
				value -- Try to get image for Prod-Season
          from tx_inv_content
         where inv_no=@pds_no
           and content_type=17 -- Prod Seas Image
        
        if @img_source is null -- Failing that, try image for Production
            select @img_source=
				value
              from tx_inv_content
             where inv_no=@pd_no
               and content_type=9 -- Prod Image

        if @img_source is null -- Failing that, try image for Calendar
            select @img_source=
				value
              from tx_inv_content
             where inv_no=@pds_no
               and content_type=8 -- Cal Image
               
         if @img_source is null
         set @img_source = ''
        
        -- Get synopsis for performance if abailable
        set @prod_synopsis=null
        select @prod_synopsis=
				value
          from tx_inv_content
         where inv_no=@pds_no
           and content_type=11 -- Prod Synopsis

        if @prod_synopsis is null
            select @prod_synopsis=value
              from t_prod_season    pds
              join tx_inv_content   cnt on cnt.inv_no=pds.prod_no
                                       and cnt.content_type=11 -- Prod Synopsis
             where pds.prod_season_no=@pds_no
             
        if @prod_synopsis is null
            set @prod_synopsis='' --@pds_desc
        
        -- Add perf to page display
        set @PageText=isnull(@PageText,@msg_header)
                     +'<hr style="height:1px; background-color:#000;" />'
        
                    
        if isnull(@img_source,'')>''
            set @PageText=@PageText
                    +isnull('<IMG SRC='''+@img_source+''' width="127"><br>','')
        else
            set @PageText=@PageText + ' <br>' -- '[NO IMAGE AVAILABLE]<br>'
        
        
        
        set @PageText=isnull(@PageText,@msg_header)+'<br>'
				+isnull(@pds_desc,'') +case when isnull(@buy_perf_no,0) > 0 then '&nbsp' +'- '+@buy_perf_dt else '' END
				+'<br><br>'
                +@button+'value="'+@cst_btn_label+'" '
                +case when isnull(@buy_perf_no,0) = 0 then
                'onclick="location.href=''../single/psDetail.aspx?psn='
                +cast(@pds_no as varchar)+'''; "/> <br>'
                else 
                'onclick="location.href=''../single/SelectSeating.aspx?p='
                +cast(@buy_perf_no as varchar)+'''; "/> <br>'END 
                +'<br>'
                +@prod_synopsis
                +'<br><br>'

        
        fetch pds_cur into @buy_perf_no, @pds_no, @pds_desc, @pd_no, @buy_perf_dt
        END
    
    deallocate pds_cur

     --if @PageText is not null
        set @PageText=@PageText
                    +'<br>'+@button+'value="  CHECKOUT  " '
			        +'onclick="location.href=''../cart/precart.aspx?p=901''; "/> '
			        +'&nbsp' +@cst_btn_text+'<br><br>'
                 				
---------------
End_Pre_Selected_list_perfs:
---------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
FINISHED_PRESELECTION_BTN:       -- End the PreSelected Perfs Loop
-----------------------------------------------------------------------

  if not exists (select * from lt_preselected_perfs where sessionkey = @SessionKey 
			and processed = 'N')
    delete lt_web_session_variable
	 where sessionkey=@sessionkey 
	   and name='PreSelected_Perfs_Loop'

    if @li_seq_no is not null
     and not exists(select * from lt_web_session_Variable where Name='Finished_PreSelected_Perfs_'+CAST(@li_seq_no as varchar))
    insert lt_web_session_Variable values(@sessionkey,'Finished_PreSelected_Perf_'+CAST(@li_seq_no as varchar),'OK')


-------------
End_PRE_SELECTED_PERFS:
-------------

   GoTo RETURN_TO_WEB

--------------
Discount_Mode:
--------------
    -- First we must create an order by inserting a cont and deleting it
    if not exists(select * from T_WEB_ORDER where sessionkey=@SessionKey)
        BEGIN
        exec lwp_CLR_AddContribution
            @ApiUrl         =@N_API_URL
           ,@SessionKey     =@N_session_key
           ,@Amount         =1
           ,@accountmethod  =19 -- On Account 

        delete cnt
          from T_WEB_ORDER          ord
          join T_WEB_CONTRIBUTION   cnt on cnt.order_no=ord.order_no
         where ord.sessionkey=@SessionKey
         
        select @mos=mos from T_WEB_ORDER where sessionkey=@SessionKey
        END
        
    if @Validate_Point=902 -- Matinee Packages
        BEGIN
        select   @cst_btn_label=Button_TEXT
                ,@cst_btn_text=Short_TEXT
                ,@cst_page_msg=Long_TEXT
          from LTR_TNEWCustom_Content
         where Content_Type='Matinee_Pkg_Msg'
     
        set @button=@button+' value="'+@cst_btn_label+'" '
           +'onclick="location.href=''../Default.aspx?promo=MatineePackages'';'
           +' "/> '+@cst_btn_text
        END
    -- DGH EDIT --
    --else
    --    BEGIN
    --   select   @cst_btn_label=Button_TEXT
    --            ,@cst_btn_text=Short_TEXT
    --            ,@cst_page_msg=Long_TEXT
    --      from LTR_TNEWCustom_Content
    --     where Content_Type='Discount_Pkg_Msg'
         
    --    set @button=@button+' value="'+@cst_btn_label+'" '
    --       +'onclick="location.href=''../Default.aspx'';'
    --       +' "/> '+@cst_btn_text
    --    END
        
    set @PageText=@msg_header
       +@cst_page_msg+'<br><br>'
       +@button

-------------
End_Dsc_Mode:
-------------
    GoTo RETURN_TO_WEB
    
-------------
Add_Cnt_BTN:
-------------
    SET @cont_amt=@validate_point - 1900000000
    
    IF @cont_amt=99999999
        SELECT @cont_amt=cast(value AS money)
          FROM lt_web_session_Variable
         WHERE SessionKey=@sessionkey
           AND Name='Round_Up'
           
    SET @account_fund = (SELECT MAX(value) FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Round_Up_Msg')
    
    IF @account_fund IS NULL 
		GoTo End_Add_Cnt_BTN

    IF @cont_amt BETWEEN 1 AND 999999
        EXEC lwp_CLR_AddContribution
            @ApiUrl         =@N_API_URL
           ,@SessionKey     =@N_session_key
           ,@Amount         =@cont_amt
           ,@AccountMethod  =@account_fund --use to send contribution to specified on account method
         --,@FundNo			=@account_fund --use to send contribution to specified fund

    UPDATE lt_web_session_Variable
       SET Value='2'
     WHERE SessionKey=@sessionkey
       AND Name='Gift_Asked'
           
    SET @PageText ='<script type="text/javascript">document.location.href '
                  +'= ''../checkout/checkout.aspx'';</script>'

-----------------
End_Add_Cnt_BTN:
-----------------
    GoTo RETURN_TO_WEB


/**********************************************************************
                   MODULES FOR VALIDATION POINTS
**********************************************************************/

-----------------------------------------------------------------------
SINGLE_ADDED:       -- Single ticket lineitem added to cart
-----------------------------------------------------------------------

 
 if @mos NOT IN(@rules_mos, @3_or_more_MOS)
    GoTo End_Messaging_rules
------------------
--Messaging_Rules
------------------
--Evaluate price and message against LTR_TNEWCustom_Disc_Message
				
SELECT	 @cst_page_msg = ISNULL(cdm.Message_Text, '')
		,@disable_checkout = ISNULL(cdm.Disable_Checkout, 'N')
	FROM LTR_TNEWCustom_Disc_Message cdm
		WHERE cdm.Num_Perfs_Kwd = ISNULL(@total_kwd_perfs, 0)
			AND cdm.Num_Perfs_Total = ISNULL(@total_perfs, 0)
			AND cdm.inactive <>'Y'
        
IF @disable_checkout = 'Y'
	BEGIN
		-- Find month of last purchase in cart
        select @month=MONTH(perf_dt)
              ,@year=YEAR(perf_dt)
          from T_PERF
         where perf_no=@perf_no
         
         
         
        select @cst_btn_label=ISNULL(Button_TEXT, 'Continue Shopping')
              ,@cst_btn_text=ISNULL(Short_TEXT, 'Click to Continue Shopping')
          from LTR_TNEWCustom_Content
         where Content_Type='Continue_Shopping'
        
        set @PageText=@msg_header
           +@cst_page_msg+'<br><br>'
           /*+@button+' value="'+@cst_btn_label+'" '
           +'onclick="location.href=''../single/eventlisting.aspx'';'
           +' "/> '+@cst_btn_text+'<br><br>'*/
            +case when exists(select top 1 * from lt_preselected_perfs where sessionKey = @sessionkey 
					and processed = 'N') then ''
           else @button+' value="'+@cst_btn_label+'" '
           +'onclick="location.href=''../single/eventlisting.aspx'';'
           +' "/> '+@cst_btn_text+'<br><br>' END
	END
ELSE
	BEGIN
		-- Find month of last purchase in cart
        select @month=MONTH(perf_dt)
              ,@year=YEAR(perf_dt)
          from T_PERF
         where perf_no=@perf_no
         
        select @cst_btn_label=ISNULL(Button_TEXT, 'Continue Shopping')
              ,@cst_btn_text=ISNULL(Short_TEXT, 'Continue Shopping')
          from LTR_TNEWCustom_Content
         where Content_Type='Continue_Shopping'
        
        set @PageText=@msg_header
           +@cst_page_msg+'<br><br>'
           +case when exists(select top 1 * from lt_preselected_perfs where sessionKey = @sessionkey 
					and processed = 'N') then ''
           else @button+' value="'+@cst_btn_label+'" '
           +'onclick="location.href=''../single/eventlisting.aspx'';'
           +' "/> '+@cst_btn_text+'<br><br>' END
           
         select @cst_btn_label2=ISNULL(Button_TEXT, 'Finished')
              ,@cst_btn_text2=ISNULL(Short_TEXT, 'Proceed to Checkout')
          from LTR_TNEWCustom_Content
         where Content_Type='Finished_Shopping'
           
        set @PageText=@PageText
           +@button+'value="'+@cst_btn_label2+'" '
           +'onclick="location.href=''../cart/cart.aspx?''; "/> ' -- Finished Button
           +'&nbsp&nbsp&nbsp'+@cst_btn_text2+'<br>'
	
	END
 
------------------
End_Messaging_rules:
------------------

	if exists(select * from lt_web_session_variable 
                      where sessionkey=@sessionkey
                        and name='PreSelected_Perfs_Loop'
						and value='Active'       )
	    GoTo Display_PRE_SELECTED_PERFS
    else
        GoTo RETURN_TO_WEB
        
------------
End_Sng_Add:
------------

-----------------------------------------------------------------------
AUX_SNG_ADDED:      -- Auxiliary Single ticket lineitem added to cart
-----------------------------------------------------------------------
------------
End_Aux_Sng:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
SUBSCRIPT_ADDED:    -- Subscription lineitem added to cart
-----------------------------------------------------------------------
------------
End_Sub_Add:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
AUX_SUB_ADDED:      -- Auxiliary Subscription lineitem added to cart
-----------------------------------------------------------------------
------------
End_Aux_Sub:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
RENEWAL_ADDED:      -- Subscription Renewal lineitem added to cart
-----------------------------------------------------------------------
------------
End_Ren_Add:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
AUX_REN_ADDED:      -- Aux Subscription Renewal lineitem added to cart
-----------------------------------------------------------------------
------------
End_Aux_Ren:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
CONT_ADDED:         -- Contribution added to cart
-----------------------------------------------------------------------
------------
End_Cnt_Add:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
CART_DELETION: -- Item deleted (set ACTION_URL in LTR_TNEW_VALIDATE_CART)
-----------------------------------------------------------------------
------------
End_Crt_Del:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
CUST_LOGIN:     -- Customer Logged-in (add query string to login URL) 
-----------------------------------------------------------------------
------------
End_Cst_Lgn:
------------
    GoTo RETURN_TO_WEB

-----------------------------------------------------------------------
CHECKOUT:       -- Checkout page
-----------------------------------------------------------------------
if @mos NOT IN (@rules_mos, @matinee_mos) 
	GoTo End_perf_limit_check 
	
-- AE 2014--
-- if @total_kwd_perfs >= 3 --= @total_perfs --if cart is all HUB, ok to check out.
--	GoTo End_perf_limit_check

-- DGH 2014--
if @total_kwd_perfs = @total_perfs --if cart is all HUB, ok to check out.
	GoTo End_perf_limit_check
	
---------------------------------------------
-- Enforce 3-show minimum for package pricing
---------------------------------------------

    if (select COUNT(distinct wli.perf_no)
          from T_WEB_LINEITEM   wli
         where wli.order_no=@order_no
		) <3 
     BEGIN   
        -- Find month of last purchase in cart
        select @month=MONTH(perf_dt)
              ,@year=YEAR(perf_dt)
          from T_PERF
         where perf_no=@perf_no
         
        select @cst_btn_label=Button_TEXT
              ,@cst_btn_text=Short_TEXT
              ,@cst_page_msg=Long_TEXT
          from LTR_TNEWCustom_Content
         where Content_Type='Checkout_Limit_Msg'
        
        set @PageText=@msg_header
           +@cst_page_msg+'<br><br>'
           +@button+' value="'+@cst_btn_label+'" '
           +'onclick="location.href=''../single/eventlisting.aspx'';'
           +' "/> '+@cst_btn_text+'<br><br>'
     END      
 ------------
End_perf_limit_check:
------------    
------------------------
-- Gift Ask
------------------------
--If the messaging for gift ask and round up is not configured, we will skip the ask. 
IF NOT EXISTS(SELECT Value FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Round_Up_Msg')
	OR EXISTS(SELECT * FROM LTR_TNEWCustom_Content WHERE Content_Type = 'Round_Up_Msg' AND inactive = 'Y')
		GoTo End_Gft_Ask

--If the cusotmer has a constituencey specified in LTR_TNEWCustom_Content we will skip the ask		
SET @constituency = (SELECT Constituency FROM LTR_TNEWCustom_Content WHERE Content_Type='Round_Up_Msg')
IF @constituency IN (Select constituency from TX_CONST_CUST where customer_no = @customer_no)
	GoTo End_Gft_Ask
	
--If we have already asked twice, or they already have a membership skip the ask. 	
IF EXISTS(SELECT * FROM lt_web_session_Variable
           WHERE SessionKey=@sessionkey AND Name='Gift_Asked' AND Value='2')
	OR EXISTS(SELECT * FROM T_WEB_CONTRIBUTION
           WHERE order_no=@order_no )
		GOTO End_Gft_Ask

        --Track number of times Checkout Ask has been made
        IF NOT EXISTS(SELECT * FROM lt_web_session_Variable
                   WHERE SessionKey=@sessionkey AND Name='Gift_Asked')
            INSERT lt_web_session_Variable (SessionKey,Name,Value)
                VALUES(@sessionkey, 'Gift_Asked', '1')
        ELSE
            UPDATE lt_web_session_Variable
               SET Value='2'
             WHERE SessionKey=@sessionkey
               AND Name='Gift_Asked'

        SET @pagetext=COALESCE(@pagetext, @msg_header)
           -- Stop Return key from triggering SUBMIT on page forms
           +'<script type="text/javascript">'
           +'document.onkeydown = function(e){'
           +'  e = e? e : window.event;'
           +'  var k = e.keyCode? e.keyCode : e.which? e.which : null;'
           +'  if (k == 13){'
           +'      if (e.preventDefault)'
           +'          e.preventDefault();'
           +'      return false;'
           +'      }'
           +'  return true;'
           +'};'
           +'</script>'
           
           -- Process the Other Amount box
           +'<SCRIPT type="text/javascript">'
           +'    function processData() {'
           +'        gift = document.getElementById("cont").value;'
           +'        gift = gift.replace(",", ""); '
           +'        gift = gift.replace("$", ""); '
           +'        if (gift == parseInt(gift) || gift == parseFloat(gift)){ '
           +'            parm=1900000000 + parseInt(gift); '
           +'            document.location.href = "../cart/precart.aspx?p="+parm.toString();} '
           +'        else {'
           +'            alert("You may enter a whole number for Other Gift Amount"); }'
           +'    }'
           +'</SCRIPT>'
           
        -- Calculate Round-up gift based on cart total
        EXEC WP_GET_CART_TOTALS
            @sessionkey   = @sessionkey
           ,@order_total  = @amt_1 output
        
        -- Start with 2% of total as gift ask amount
        SET @amt_2=ROUND(@amt_1 * .02,2,-1)

        -- Choose level to round up to
			SET @level = CASE
				WHEN @amt_1 <	100 THEN  10
				WHEN @amt_1 <	350 THEN  20
				WHEN @amt_1 <	750 THEN  50
				WHEN @amt_1 <100000 THEN  100
				ELSE					  10
			    END
        

        -- Round up to nearest whole dollar
        WHILE (@amt_1 + @amt_2) < round((@amt_1 + @amt_2),0,-1)
            SET @amt_2 += .01
        WHILE (@amt_1 + @amt_2) > round((@amt_1 + @amt_2),0,-1)
            SET @amt_2 -= .01

        -- Round down to nearest multiple of level
        WHILE (@amt_1 + @amt_2 ) % @level > 0
            SET @amt_2 -= 1
        
        -- Adjust if calculated ask is too high or too low
        IF      @amt_2 < @level/3   SET @amt_2 += @level
        ELSE IF @amt_2 > @level     SET @amt_2=@level
        ELSE IF @amt_2=0            SET @amt_2=1

        DELETE lt_web_session_variable WHERE sessionkey=@sessionkey AND name='Round_UP'     
        INSERT lt_web_session_variable (SessionKey,Name,Value)
                                VALUES(@sessionkey, 'Round_Up', CAST(@amt_2 AS varchar))
                                

        -- Display buttons
		SELECT  @ga_up_btn=Button_TEXT
				,@ga_up_btn_text=ISNULL(Short_TEXT, '')
				,@ga_header	=ISNULL(Long_TEXT, 'Please consider rounding up your order to support us!')
		  FROM LTR_TNEWCustom_Content
		 WHERE Content_Type='Round_Up_Msg'
		 
		 SELECT  @ga_other_btn=Button_TEXT
				,@ga_other_btn_text=ISNULL(Short_TEXT, '')
		  FROM LTR_TNEWCustom_Content
		 WHERE Content_Type='Round_Up_Msg_Other'
		 
		 SELECT  @ga_no_btn=Button_TEXT
				,@ga_no_btn_text=ISNULL(Short_TEXT, '')
				,@ga_footer	=ISNULL(Long_TEXT,'')
		  FROM LTR_TNEWCustom_Content
		 WHERE Content_Type='Round_Up_Msg_No'
         
		SET @PageText=ISNULL(@PageText,'')
		   +@ga_header+'<br><br>'
        
        SET @pagetext=@PageText
           +@button+'value="   '+COALESCE(@ga_up_btn,'Round Up Your Order to')+ ' $'+CAST(CAST(@amt_1+@amt_2 as int) as varchar)+'   " '
           +'   onclick="location.href=''../cart/precart.aspx?p=1999999999''"; />'
           +'&nbsp;&nbsp;&nbsp;'
           +@ga_up_btn_text+'<BR><BR>'
           +'<INPUT TYPE="button" class="btnStyle" ID="contOK" VALUE="   '+COALESCE(@ga_other_btn,'Make A Gift of Another Amount')+ '   " '
           +'   onclick="processData();" /> &nbsp;&nbsp;&nbsp;'
           +'<INPUT TYPE="text" style="width:60px;height:18px;" NAME="contAmt" ID="cont" VALUE="" '
           +'   onkeydown="if (event.keyCode == 13){event.returnValue=false; event.cancel = true; '
           +'             document.getElementById(''contOK'').click()}" /> '
           +'&nbsp;&nbsp;&nbsp;'+@ga_other_btn_text
        
        
        SET @pagetext=@PageText+'<br><br>'
           +@button+'value="   '+COALESCE(@ga_no_btn,'No, Thank You') +'   " '
           +'  onclick="location.href=''../cart/precart.aspx?p=1900000000''"; />'
           +'&nbsp;&nbsp;&nbsp;' -- No Thanks message here
           +@ga_no_btn_text+'<br><br>'
           
        SET @PageText=isnull(@PageText,'')
		   +@ga_footer+'<br><br>'   
                    
                     
        GoTo RETURN_TO_WEB

------------
End_Gft_Ask:
------------
     
------------
End_Chk_Out:
------------
    GoTo RETURN_TO_WEB


RETURN -- (You can't really get here if you've coded properly above)

/**********************************************************************
 If any PageText has been generated above, return with it now
**********************************************************************/

----------------------------------|
--------------------            --|
Rollback_With_Error:            --|
--------------------            --|
Rollback Tran                   --|
                                --|
--------------                  --| Keep this block together
RETURN_TO_WEB:                  --|
--------------                  --|
if @PageText is not null        --|
    select @PageText            --|
RETURN                          --|
----------------------------------|

/**********************************************************************
 SOME USEFUL ROUTINES FOR VALIDATION PROCESSING...
***********************************************************************
------- For Testing, find current web order and display info--------
declare @session  varchar(64)
       ,@order    int
       ,@customer int

select top 1 @session=sessionkey, @order=order_no, @customer=customer_no
  from T_WEB_ORDER 
 --where customer_no=759 
 --where sessionkey='9XCN7GSAQ16JIRJ510I0JW6LBE48QKNFTA01F43XE42Q1RU91U68FGDWCVYLR363'
 --where order_no=530
 order by order_dt desc
select customer_no, fname, lname from T_CUSTOMER       where customer_no=@customer
select 'SessVar',* from t_web_session_Variable         where SessionKey=@session
select 'SessSessr',* from t_web_session_Session        where SessionKey=@session
select 'ORDER',* from T_WEB_ORDER                      where SessionKey=@session
select 'LTM',* from T_WEB_LINEITEM                     where order_no=@order
select 'SLI',* from T_WEB_Sub_LINEITEM                 where order_no=@order
select 'CONT',* from T_WEB_CONTRIBUTION                where order_no=@order
select 'FEE',* from T_WEB_SLI_FEE                      where order_no=@order
---------------------------------------------------------------------

----######## Stick this in code at point to debug ########
set @pkg_no=@@CURSOR_ROWS
set @PageText='############  Roger''s Debugging Code  ###########'
+'<br>SessionKey='+@sessionkey
+'<br>Order_no='+CAST (isnull(@order_no,0) as varchar)
+'<br>MOS='+CAST (isnull(@mos,0) as varchar)
+'<br>Validation='+CAST (isnull(@validate_point,0) as varchar)
+'<br>li_no='+CAST(isnull(@li_no,0) as varchar)
+'<br>li_seq_no='+CAST(isnull(@li_seq_no,0) as varchar)
+'<br>Pkg Season='+cast(isnull(@season,0) as varchar)
+'<br>Pkg_no='+cast(isnull(@pkg_no,0) as varchar)
+'<br>Pkg_code='+cast(isnull(@pkg_code,'') as varchar)
+'<br>Perf_no='+cast(isnull(@perf_no,0) as varchar)
+'<br>PriceType='+CAST(isnull(@price_type,0) as varchar)
+'<br>Seats='+cast(isnull(@seats,0) as varchar)
+'<br>Zone='+cast(isnull(@zone_no,0) as varchar)
+'<br>Discount No='+cast(isnull(@discount_no,0) as varchar)
+'<br>Num Perfs='+cast(isnull(@num_perfs,0) as varchar)
+'<br>Perf Count='+cast(isnull(@perf_count,0) as varchar)
+'<br>Buy_Perf_no='+cast(isnull(@buy_perf_no,0) as varchar)
+'<br>Buy_PriceType='+CAST(isnull(@buy_pricetype,0) as varchar)
+'<br>Buy_Price_Str='+isnull(@buy_price_str,'')
+'<br>Buy seats='+cast(isnull(@buy_seats,0) as varchar)
+'<br>Get_Perf_no='+cast(isnull(@Get_perf_no,0) as varchar)
+'<br>Get_PriceType='+CAST(isnull(@get_pricetype,0) as varchar)
+'<br>Get seats='+cast(isnull(@get_seats,0) as varchar)
+'<br>Num seats='+cast(isnull(@num_seats,0) as varchar)
+'<br>Min seats='+cast(isnull(@min_seats,0) as varchar)
+'<br>Cart seats='+cast(isnull(@cart_seats,0) as varchar)
+'<br>Req seats='+cast(isnull(@req_seats,0) as varchar)
+'<br>N_SessionKey='+cast(isnull(@N_session_key,0) as varchar(128))
+'<br>N_PriceTypes='+cast(isnull(@N_price_type,0) as varchar)
+'<br><br>##################################################'
+'<br><br>'+@back_btn
goto return_to_web
--#####################################################
       

-- Add BUTTON for user response
        set @PageText = @PageText
                    +'<br>'
                    +@button+' value="XXX XXX" '
                    +'onclick="location.href=''../cart/precart.aspx?p=999001'';'
                    +' "/> I wish to add Gift Aid.'

-- Redirect to another page (presumably after performing some action)
       set @PageText='<meta HTTP-EQUIV="REFRESH" content="0; url=../dev/contribute.aspx?don=1&fieldAmt=&u=">'
-- OR  set @PageText='<script language="javascript">document.location.href = ''../checkout/checkout.aspx'';</script>'


-- Example of Images as hyperlinks that can be constructed from TX_INV_CONTENT
    +'<CENTER><h2>If you are ordering season tickets, you can now add these Alley favorites '
    +'to your order by clicking on the images below.  <BR>You may buy as many as 9 tickets for '
    +'you and your friends and family!  <BR>Season ticketholders always get priority seating '
    +'and great prices when adding on tickets to special events.<BR><BR>'
    
    +'<table width="75%" border="0">'
    
    +'<tr><td><CENTER><a href=''../auxiliary/Reserve.aspx?p=624''>'
    +'<IMG border="0" SRC="'
    +(select value from TX_INV_CONTENT where inv_no=999 and content_type=999)
    +'"></CENTER></A></td>'
    
    +'<tr><td><CENTER><a href=''../auxiliary/Reserve.aspx?p=629''>'
    +'<IMG border="0" SRC="'
    +(select value from TX_INV_CONTENT where inv_no=999 and content_type=999)
    +'"></CENTER></A></td>'

    +'<tr><td><CENTER><a href=''../auxiliary/Reserve.aspx?p=636''>'
    +'<IMG border="0" SRC="'
    +(select value from TX_INV_CONTENT where inv_no=999 and content_type=999)
    +'"></CENTER></A></td>'

    +'</table>

**********************************************************************/
