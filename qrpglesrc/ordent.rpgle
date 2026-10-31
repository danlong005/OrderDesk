**free
// ORDENT: enter an order. The header (customer, PO, ship date) and up to 30
// lines (item, quantity) are on one screen. Enter checks it and prices the
// lines, F4 picks the customer or an item from a window (CUSTSEL, ITEMSEL),
// and F10 places the order. An order that takes the customer over its credit
// limit, with its open and held orders, is placed as HELD.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f ORDENTD workstn sfile(ORDSFL:rrn) indds(ind);
dcl-f CUSTMAST keyed;
dcl-f ITEMMAST keyed;
dcl-f ORDHDR keyed usage(*input:*output);
dcl-f ORDHCUST keyed rename(ORDHR:ORDHCR);
dcl-f ORDDTL usage(*output);

dcl-ds ind len(99);
   exitKey ind pos(3);
   promptKey ind pos(4);
   clearKey ind pos(5);
   placeKey ind pos(10);
   cancelKey ind pos(12);
   sflDsp ind pos(31);
   sflDspCtl ind pos(32);
   sflClr ind pos(33);
   sflEnd ind pos(34);
   customerError ind pos(51);
   shipError ind pos(52);
   itemError ind pos(61);
   quantityError ind pos(62);
end-ds;

dcl-pr CUSTSEL extpgm('CUSTSEL');
   picked zoned(6:0);
end-pr;
dcl-pr ITEMSEL extpgm('ITEMSEL');
   picked char(10);
end-pr;

dcl-c LINES 30;
   // the next order number, kept in a data area
dcl-s nextOrder packed(7:0) dtaara('ODNEXTORD');

dcl-s rrn packed(4:0);
dcl-s lineCount int(10);
dcl-s message varchar(78);

newOrder();

dow *on;
   MSG = message;
   message = '';
   write FOOTER;
   exfmt ORDCTL;
   customerError = *off;
   shipError = *off;
   TOPRRN = 1;

   select;
   when exitKey or cancelKey;
      leave;
   when clearKey;
      newOrder();
   when promptKey;
      prompt();
      checkOrder();
   when placeKey;
      if checkOrder();
         placeOrder();
      endif;
   other;
      if checkOrder() and lineCount > 0;
         message = 'The order is ready. Press F10 to place it.';
      endif;
   endsl;
enddo;

*inlr = *on;
return;


   // An empty order: no header, and every line blank.
dcl-proc newOrder;
   HCUST = 0;
   HCNAME = '';
   HPO = '';
   HSHIP = 0;
   HCRLMT = 0;
   HTOTAL = 0;
   TOPRRN = 1;

   sflDsp = *off;
   sflDspCtl = *off;
   sflClr = *on;
   write ORDCTL;
   sflClr = *off;

   itemError = *off;
   quantityError = *off;
   for rrn = 1 to LINES;
      clear ORDSFL;
      SLINE = rrn;
      write ORDSFL;
   endfor;
   sflDsp = *on;
   sflDspCtl = *on;
   sflEnd = *on;
end-proc;


   // F4 on the customer or on an item: pick one from a window.
dcl-proc prompt;
   dcl-s customer zoned(6:0);
   dcl-s item char(10);

   if CSRFLD = 'HCUST';
      CUSTSEL(customer);
      if customer <> 0;
         HCUST = customer;
      endif;
   elseif CSRFLD = 'SITEM' and CSRRRN > 0;
      ITEMSEL(item);
      if item <> '';
         chain CSRRRN ORDSFL;
         SITEM = item;
         update ORDSFL;
      endif;
      TOPRRN = CSRRRN;
   else;
      message = 'Put the cursor on the customer or an item, then press F4.';
   endif;
end-proc;


   // Check the header and price every line. Returns *off when something is
   // wrong; the first problem is in the message line.
dcl-proc checkOrder;
   dcl-pi *n ind;
   end-pi;
   dcl-s ok ind inz(*on);
   dcl-s firstBad packed(4:0);

   HCNAME = '';
   HCRLMT = 0;
   chain (HCUST) CUSTMAST;
   if not %found(CUSTMAST) or CMACTV <> 'Y';
      customerError = *on;
      ok = *off;
   else;
      HCNAME = CMNAME;
      HCRLMT = CMCRLMT;
   endif;

   if HSHIP <> 0;
      test(de) *iso HSHIP;
      if %error;
         shipError = *on;
         ok = *off;
      elseif %date(HSHIP : *iso) < %date();
         shipError = *on;
         ok = *off;
      endif;
   endif;

   HTOTAL = 0;
   lineCount = 0;
   for rrn = 1 to LINES;
      chain rrn ORDSFL;
      itemError = *off;
      quantityError = *off;
      SDESC = '';
      SPRICE = 0;
      SAMT = 0;
      if SITEM <> '' or SQTY <> 0;
         chain (SITEM) ITEMMAST;
         if SITEM = '';
            itemError = *on;
            lineProblem(firstBad : 'Line ' + %char(rrn) + ': type an item, '
                        + 'or press F4 to pick one.');
         elseif not %found(ITEMMAST);
            itemError = *on;
            lineProblem(firstBad : 'Line ' + %char(rrn) + ': there is no item '
                        + %trim(SITEM) + '. Press F4 to pick one.');
         else;
            SDESC = IMDESC;
            SPRICE = IMPRICE;
            if SQTY <= 0;
               quantityError = *on;
               lineProblem(firstBad : 'Line ' + %char(rrn) + ': type a quantity.');
            else;
               SAMT = SQTY * IMPRICE;
               HTOTAL += SAMT;
               lineCount += 1;
            endif;
         endif;
      endif;
      update ORDSFL;
   endfor;
   itemError = *off;
   quantityError = *off;

   if firstBad > 0;
      ok = *off;
      TOPRRN = firstBad;
   endif;
   return ok;
end-proc;


   // Remember the first line with a problem, and its message.
dcl-proc lineProblem;
   dcl-pi *n;
      firstBad packed(4:0);
      text varchar(78) const;
   end-pi;

   if firstBad = 0;
      firstBad = rrn;
      message = text;
   endif;
end-proc;


   // Write the order and its lines, then start a new one.
dcl-proc placeOrder;
   dcl-s order packed(7:0);
   dcl-s status char(10) inz('OPEN');
   dcl-s line packed(3:0);

   if lineCount = 0;
      message = 'Type at least one item and quantity.';
      return;
   endif;

   if openOrders(HCUST) + HTOTAL > HCRLMT;
      status = 'HELD';
   endif;

   in *lock nextOrder;
   order = %max(nextOrder : lastOrder() + 1);
   nextOrder = order + 1;
   out nextOrder;

   OHORD = order;
   OHCUST = HCUST;
   OHDATE = %dec(%date() : *iso);
   if HSHIP = 0;
      OHSHIP = %dec(%date() + %days(7) : *iso);
   else;
      OHSHIP = HSHIP;
   endif;
   OHSTAT = status;
   OHTOTAL = HTOTAL;
   OHPO = HPO;
   write ORDHR;

   for rrn = 1 to LINES;
      chain rrn ORDSFL;
      if SITEM <> '' and SQTY > 0;
         line += 1;
         ODORD = order;
         ODLINE = line;
         ODITEM = SITEM;
         ODQTY = SQTY;
         ODPRICE = SPRICE;
         ODAMT = SAMT;
         write ORDDR;
      endif;
   endfor;

   if status = 'HELD';
      message = 'Order ' + %char(order) + ' placed, and held: it is over '
              + %trim(HCNAME) + '''s credit limit.';
   else;
      message = 'Order ' + %char(order) + ' placed for ' + %trim(HCNAME) + '.';
   endif;
   newOrder();
end-proc;


   // The total of a customer's open and held orders.
dcl-proc openOrders;
   dcl-pi *n packed(13:2);
      customer zoned(6:0) const;
   end-pi;
   dcl-s total packed(13:2);

   setll (customer) ORDHCUST;
   reade (customer) ORDHCUST;
   dow not %eof(ORDHCUST);
      if OHSTAT = 'OPEN' or OHSTAT = 'HELD';
         total += OHTOTAL;
      endif;
      reade (customer) ORDHCUST;
   enddo;
   return total;
end-proc;


   // The highest order number used, so that the data area never gives one
   // twice (after the sample data is loaded, for instance).
dcl-proc lastOrder;
   dcl-pi *n packed(7:0);
   end-pi;

   setgt *hival ORDHDR;
   readp ORDHDR;
   if %eof(ORDHDR);
      return 0;
   endif;
   return OHORD;
end-proc;
