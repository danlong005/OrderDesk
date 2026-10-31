**free
// CUSTWRK: Work with Customers. Every customer in a subfile by name, from
// the name typed in "Position to". Options call CUSTMNT to change or display
// one, ORDWRK for its orders, and delete it after a confirmation window.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f CUSTWRKD workstn sfile(CUSTSFL:rrn) indds(ind);
dcl-f CUSTNAME keyed rename(CUSTR:CUSTNR);
dcl-f CUSTMAST keyed usage(*update:*delete);
dcl-f ORDHCUST keyed rename(ORDHR:ORDHCR);

dcl-ds ind len(99);
   exitKey ind pos(3);
   refreshKey ind pos(5);
   addKey ind pos(6);
   deleteKey ind pos(10);
   cancelKey ind pos(12);
   sflDsp ind pos(31);
   sflDspCtl ind pos(32);
   sflClr ind pos(33);
   sflEnd ind pos(34);
end-ds;

dcl-pr CUSTMNT extpgm('CUSTMNT');
   mode char(1) const;
   customer zoned(6:0) const;
end-pr;
dcl-pr ORDWRK extpgm('ORDWRK');
   customer zoned(6:0) const;
end-pr;

dcl-s rrn packed(4:0);
dcl-s count packed(4:0);
   // the subfile record to show at the top after a reload
dcl-s keepRrn packed(4:0) inz(1);
dcl-s position char(20);
dcl-s message varchar(78);

loadCustomers();

dow *on;
   MSG = message;
   message = '';
   write FOOTER;
   exfmt CUSTCTL;

   select;
   when exitKey or cancelKey;
      leave;
   when refreshKey;
      POSNAM = '';
      position = '';
      keepRrn = 1;
   when addKey;
      CUSTMNT('A' : 0);
   when POSNAM <> position;
      position = POSNAM;
      keepRrn = 1;
   other;
      doOptions();
   endsl;
   loadCustomers();
enddo;

*inlr = *on;
return;


   // Fill the subfile with every customer from the position-to name on.
dcl-proc loadCustomers;
   sflDsp = *off;
   sflDspCtl = *off;
   sflClr = *on;
   write CUSTCTL;
   sflClr = *off;

   count = 0;
   if position = '';
      setll *loval CUSTNAME;
   else;
      setll (position) CUSTNAME;
   endif;
   read CUSTNAME;
   dow not %eof(CUSTNAME) and count < 9999;
      count += 1;
      rrn = count;
      SOPT = '';
      SCUST = CMCUST;
      SNAME = CMNAME;
      SCITY = CMCITY;
      SSTATE = CMSTATE;
      SACTV = CMACTV;
      write CUSTSFL;
      read CUSTNAME;
   enddo;

   sflDsp = (count > 0);
   sflDspCtl = *on;
   sflEnd = *on;
   if count = 0;
      TOPRRN = 1;
      if message = '';
         message = 'No customers to show. Press F6 to add one.';
      endif;
   else;
      TOPRRN = %min(keepRrn : count);
   endif;
end-proc;


   // Act on every option typed in the subfile.
dcl-proc doOptions;
   readc CUSTSFL;
   dow not %eof(CUSTWRKD);
      keepRrn = rrn;
      select;
      when SOPT = '2';
         CUSTMNT('C' : SCUST);
      when SOPT = '4';
         deleteCustomer(SCUST : SNAME);
      when SOPT = '5';
         CUSTMNT('D' : SCUST);
      when SOPT = '7';
         ORDWRK(SCUST);
      when SOPT <> '';
         message = 'Option ' + SOPT + ' is not valid. Use 2, 4, 5 or 7.';
      endsl;
      readc CUSTSFL;
   enddo;
end-proc;


   // Delete a customer once F10 confirms it, unless it has orders.
dcl-proc deleteCustomer;
   dcl-pi *n;
      customer zoned(6:0) const;
      name char(30) const;
   end-pi;

   setll (customer) ORDHCUST;
   if %equal(ORDHCUST);
      message = 'Customer ' + %char(customer) + ' has orders and cannot be deleted.';
      return;
   endif;

   DCUST = customer;
   DNAME = name;
   exfmt DLTWIN;
   if not deleteKey;
      return;
   endif;

   chain (customer) CUSTMAST;
   if %found(CUSTMAST);
      delete CUSTR;
      message = 'Customer ' + %char(customer) + ' deleted.';
   endif;
end-proc;
