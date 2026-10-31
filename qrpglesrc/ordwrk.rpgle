**free
// ORDWRK: Work with Orders, newest first. Filtered by status and customer
// (CUSTWRK option 7 passes one). Options display an order (ORDDSP), cancel
// an open or held order, and release a held one; F6 enters a new order.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f ORDWRKD workstn sfile(ORDSFL:rrn) indds(ind);
dcl-f ORDHDR keyed usage(*update);
dcl-f ORDHCUST keyed rename(ORDHR:ORDHCR);
dcl-f ORDHSTAT keyed rename(ORDHR:ORDHSR);
dcl-f CUSTMAST keyed;

dcl-pi *n;
   customer zoned(6:0) const options(*nopass);
end-pi;

dcl-ds ind len(99);
   exitKey ind pos(3);
   refreshKey ind pos(5);
   newKey ind pos(6);
   cancelKey ind pos(12);
   sflDsp ind pos(31);
   sflDspCtl ind pos(32);
   sflClr ind pos(33);
   sflEnd ind pos(34);
end-ds;

dcl-pr ORDDSP extpgm('ORDDSP');
   order zoned(7:0) const;
end-pr;
dcl-pr ORDENT extpgm('ORDENT');
end-pr;

dcl-s rrn packed(4:0);
dcl-s count packed(4:0);
dcl-s keepRrn packed(4:0) inz(1);
dcl-s message varchar(78);
   // the filters the subfile was loaded with
dcl-s status char(10);
dcl-s forCustomer zoned(6:0);

if %parms >= 1;
   FCUST = customer;
endif;
loadOrders();

dow *on;
   MSG = message;
   message = '';
   write FOOTER;
   exfmt ORDCTL;

   select;
   when exitKey or cancelKey;
      leave;
   when refreshKey;
      keepRrn = 1;
   when newKey;
      ORDENT();
   when FSTAT <> status or FCUST <> forCustomer;
      keepRrn = 1;
   other;
      doOptions();
   endsl;
   loadOrders();
enddo;

*inlr = *on;
return;


   // Fill the subfile with the orders the filters choose, newest first.
dcl-proc loadOrders;
   sflDsp = *off;
   sflDspCtl = *off;
   sflClr = *on;
   write ORDCTL;
   sflClr = *off;
   count = 0;

   FSTAT = %upper(FSTAT);
   if FSTAT <> '' and FSTAT <> 'OPEN' and FSTAT <> 'HELD'
      and FSTAT <> 'SHIPPED' and FSTAT <> 'CANCELLED';
      message = 'Status ' + %trim(FSTAT) + ' is not valid.';
      FSTAT = '';
   endif;
   status = FSTAT;

   FCNAME = '';
   if FCUST <> 0;
      chain (FCUST) CUSTMAST;
      if %found(CUSTMAST);
         FCNAME = CMNAME;
      else;
         message = 'There is no customer ' + %char(FCUST) + '.';
         FCUST = 0;
      endif;
   endif;
   forCustomer = FCUST;

   if forCustomer <> 0;
      setll (forCustomer) ORDHCUST;
      reade (forCustomer) ORDHCUST;
      dow not %eof(ORDHCUST) and count < 9999;
         if status = '' or OHSTAT = status;
            addOrder();
         endif;
         reade (forCustomer) ORDHCUST;
      enddo;
   elseif status <> '';
      setll (status) ORDHSTAT;
      reade (status) ORDHSTAT;
      dow not %eof(ORDHSTAT) and count < 9999;
         addOrder();
         reade (status) ORDHSTAT;
      enddo;
   else;
      setgt *hival ORDHDR;
      readp(n) ORDHDR;
      dow not %eof(ORDHDR) and count < 9999;
         addOrder();
         readp(n) ORDHDR;
      enddo;
   endif;

   sflDsp = (count > 0);
   sflDspCtl = *on;
   sflEnd = *on;
   if count = 0;
      TOPRRN = 1;
      if message = '';
         message = 'No orders to show.';
      endif;
   else;
      TOPRRN = %min(keepRrn : count);
   endif;
end-proc;


   // One subfile record for the order just read.
dcl-proc addOrder;
   count += 1;
   rrn = count;
   SOPT = '';
   SORD = OHORD;
   SDATE = %char(%date(OHDATE : *iso) : *iso);
   SSTAT = OHSTAT;
   SAMT = OHTOTAL;
   chain (OHCUST) CUSTMAST;
   if %found(CUSTMAST);
      SCNAME = CMNAME;
   else;
      SCNAME = '';
   endif;
   write ORDSFL;
end-proc;


dcl-proc doOptions;
   readc ORDSFL;
   dow not %eof(ORDWRKD);
      keepRrn = rrn;
      select;
      when SOPT = '4';
         changeStatus(SORD : 'CANCELLED');
      when SOPT = '5';
         ORDDSP(SORD);
      when SOPT = '6';
         changeStatus(SORD : 'OPEN');
      when SOPT <> '';
         message = 'Option ' + SOPT + ' is not valid. Use 4, 5 or 6.';
      endsl;
      readc ORDSFL;
   enddo;
end-proc;


   // Cancel an open or held order, or release a held one.
dcl-proc changeStatus;
   dcl-pi *n;
      order zoned(7:0) const;
      newStatus char(10) const;
   end-pi;

   chain (order) ORDHDR;
   if not %found(ORDHDR);
      return;
   endif;
   if newStatus = 'CANCELLED' and OHSTAT <> 'OPEN' and OHSTAT <> 'HELD';
      message = 'Order ' + %char(order) + ' is ' + %trim(OHSTAT)
              + ' and cannot be cancelled.';
      unlock ORDHDR;
      return;
   endif;
   if newStatus = 'OPEN' and OHSTAT <> 'HELD';
      message = 'Order ' + %char(order) + ' is not held.';
      unlock ORDHDR;
      return;
   endif;

   OHSTAT = newStatus;
   update ORDHR;
   if newStatus = 'OPEN';
      message = 'Order ' + %char(order) + ' released.';
   else;
      message = 'Order ' + %char(order) + ' cancelled.';
   endif;
end-proc;
