**free
// CUSTSEL: pick a customer from a window. Lists active customers by name;
// returns the number chosen with 1, or 0 when F12 cancels.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f CUSTSELD workstn sfile(SELSFL:rrn) indds(ind);
dcl-f CUSTNAME keyed;

dcl-pi *n;
   picked zoned(6:0);
end-pi;

dcl-ds ind len(99);
   cancelKey ind pos(12);
   sflDsp ind pos(31);
   sflDspCtl ind pos(32);
   sflClr ind pos(33);
   sflEnd ind pos(34);
end-ds;

dcl-s rrn packed(4:0);
dcl-s count packed(4:0);
dcl-s position char(20);

picked = 0;
load();

dow *on;
   write SELWIN;
   exfmt SELCTL;
   if cancelKey;
      leave;
   endif;
   if SPOS <> position;
      position = SPOS;
      load();
      iter;
   endif;

   readc SELSFL;
   dow not %eof(CUSTSELD);
      if SOPT = '1';
         picked = SCUST;
         leave;
      endif;
      readc SELSFL;
   enddo;
   if picked <> 0;
      leave;
   endif;
enddo;

*inlr = *on;
return;


dcl-proc load;
   sflDsp = *off;
   sflDspCtl = *off;
   sflClr = *on;
   write SELCTL;
   sflClr = *off;

   count = 0;
   if position = '';
      setll *loval CUSTNAME;
   else;
      setll (position) CUSTNAME;
   endif;
   read CUSTNAME;
   dow not %eof(CUSTNAME) and count < 9999;
      if CMACTV = 'Y';
         count += 1;
         rrn = count;
         SOPT = '';
         SCUST = CMCUST;
         SNAME = CMNAME;
         write SELSFL;
      endif;
      read CUSTNAME;
   enddo;

   sflDsp = (count > 0);
   sflDspCtl = *on;
   sflEnd = *on;
end-proc;
