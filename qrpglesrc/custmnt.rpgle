**free
// CUSTMNT: add, change or display one customer. Called by CUSTWRK with a
// mode, A (add), C (change) or D (display), and the customer number. The
// Help key shows a window explaining the fields.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f CUSTMNTD workstn indds(ind);
dcl-f CUSTMAST keyed usage(*update:*output);

dcl-pi *n;
   mode char(1) const;
   customer zoned(6:0) const;
end-pi;

dcl-ds ind len(99);
   exitKey ind pos(3);
   cancelKey ind pos(12);
   helpKey ind pos(25);
   protect ind pos(30);
   nameError ind pos(51);
   cityError ind pos(52);
   stateError ind pos(53);
   dateError ind pos(54);
end-ds;

dcl-c STATES 'AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME +
              MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI +
              SC SD TN TX UT VT VA WA WV WI WY';

protect = (mode = 'D');
select;
when mode = 'A';
   setTitle('Add Customer');
   DCUST = nextCustomer();
   DACTV = 'Y';
   DADDED = %dec(%date() : *iso);
when mode = 'C' or mode = 'D';
   chain(n) (customer) CUSTMAST;
   if not %found(CUSTMAST);
      *inlr = *on;
      return;
   endif;
   if mode = 'C';
      setTitle('Change Customer');
   else;
      setTitle('Display Customer');
   endif;
   DCUST = CMCUST;
   DNAME = CMNAME;
   DADDR = CMADDR;
   DCITY = CMCITY;
   DSTATE = CMSTATE;
   DZIP = CMZIP;
   DPHONE = CMPHONE;
   DCRLMT = CMCRLMT;
   DACTV = CMACTV;
   DADDED = CMADDED;
other;
   *inlr = *on;
   return;
endsl;

dow *on;
   exfmt DETAIL;
   nameError = *off;
   cityError = *off;
   stateError = *off;
   dateError = *off;

   if helpKey;
      exfmt HLPWIN;
      iter;
   endif;
   if exitKey or cancelKey or mode = 'D';
      leave;
   endif;
   if valid();
      save();
      leave;
   endif;
enddo;

*inlr = *on;
return;


   // Center the title in its field on row 1.
dcl-proc setTitle;
   dcl-pi *n;
      text varchar(28) const;
   end-pi;

   TITLE = '';
   %subst(TITLE : (%len(TITLE) - %len(text)) / 2 + 1 : %len(text)) = text;
end-proc;


   // One past the highest customer number, from 100 for the first.
dcl-proc nextCustomer;
   dcl-pi *n zoned(6:0);
   end-pi;

   setgt *hival CUSTMAST;
   readp(n) CUSTMAST;
   if %eof(CUSTMAST);
      return 100;
   endif;
   return CMCUST + 1;
end-proc;


   // Check the fields; the first one in error gets its message.
dcl-proc valid;
   dcl-pi *n ind;
   end-pi;

   if DNAME = '';
      nameError = *on;
      return *off;
   endif;
   if DCITY = '';
      cityError = *on;
      return *off;
   endif;
   if %len(%trim(DSTATE)) <> 2 or %scan(DSTATE : STATES) = 0;
      stateError = *on;
      return *off;
   endif;
   test(de) *iso DADDED;
   if %error;
      dateError = *on;
      return *off;
   endif;
   return *on;
end-proc;


   // Write a new customer, or update the one being changed.
dcl-proc save;
   if mode = 'A';
      dow *on;
         CMCUST = DCUST;
         setFields();
         write(e) CUSTR;
            // someone else took the number meanwhile: take the next one
         if not %error;
            leave;
         endif;
         DCUST = nextCustomer();
      enddo;
   else;
      chain (customer) CUSTMAST;
      if %found(CUSTMAST);
         setFields();
         update CUSTR;
      endif;
   endif;
end-proc;


dcl-proc setFields;
   CMNAME = DNAME;
   CMADDR = DADDR;
   CMCITY = DCITY;
   CMSTATE = DSTATE;
   CMZIP = DZIP;
   CMPHONE = DPHONE;
   CMCRLMT = DCRLMT;
   CMACTV = DACTV;
   CMADDED = DADDED;
end-proc;
