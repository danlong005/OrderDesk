**free
// ITEMSEL: pick an item from a window, by item number. Returns the item
// chosen with 1, or blanks when F12 cancels. The main menu uses it to browse.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f ITEMSELD workstn sfile(SELSFL:rrn) indds(ind);
dcl-f ITEMMAST keyed;

dcl-pi *n;
   picked char(10);
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
dcl-s position char(10);

picked = '';
load();

dow *on;
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
   dow not %eof(ITEMSELD);
      if SOPT = '1';
         picked = SITEM;
         leave;
      endif;
      readc SELSFL;
   enddo;
   if picked <> '';
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
      setll *loval ITEMMAST;
   else;
      setll (position) ITEMMAST;
   endif;
   read ITEMMAST;
   dow not %eof(ITEMMAST) and count < 9999;
      count += 1;
      rrn = count;
      SOPT = '';
      SITEM = IMITEM;
      SDESC = IMDESC;
      SPRICE = IMPRICE;
      SONHND = IMONHND;
      write SELSFL;
      read ITEMMAST;
   enddo;

   sflDsp = (count > 0);
   sflDspCtl = *on;
   sflEnd = *on;
end-proc;
