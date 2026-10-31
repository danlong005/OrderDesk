**free
// ORDDSP: display one order, its header and its lines. Called by ORDWRK.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f ORDDSPD workstn sfile(LINSFL:rrn) indds(ind);
dcl-f ORDHDR keyed;
dcl-f ORDDTL keyed;
dcl-f CUSTMAST keyed;
dcl-f ITEMMAST keyed;

dcl-pi *n;
   order zoned(7:0) const;
end-pi;

dcl-ds ind len(99);
   sflDsp ind pos(31);
   sflDspCtl ind pos(32);
   sflClr ind pos(33);
   sflEnd ind pos(34);
end-ds;

dcl-s rrn packed(4:0);

chain (order) ORDHDR;
if not %found(ORDHDR);
   *inlr = *on;
   return;
endif;

DORD = OHORD;
DSTAT = OHSTAT;
DCUST = OHCUST;
DPO = OHPO;
DDATE = %char(%date(OHDATE : *iso) : *iso);
DSHIP = %char(%date(OHSHIP : *iso) : *iso);
DTOTAL = OHTOTAL;
chain (OHCUST) CUSTMAST;
if %found(CUSTMAST);
   DCNAME = CMNAME;
   DCITY = CMCITY;
   DSTATE = CMSTATE;
endif;

sflClr = *on;
write LINCTL;
sflClr = *off;

setll (order) ORDDTL;
reade (order) ORDDTL;
dow not %eof(ORDDTL) and rrn < 9999;
   rrn += 1;
   SLINE = ODLINE;
   SITEM = ODITEM;
   SQTY = ODQTY;
   SPRICE = ODPRICE;
   SAMT = ODAMT;
   chain (ODITEM) ITEMMAST;
   if %found(ITEMMAST);
      SDESC = IMDESC;
   else;
      SDESC = '';
   endif;
   write LINSFL;
   reade (order) ORDDTL;
enddo;

sflDsp = (rrn > 0);
sflDspCtl = *on;
sflEnd = *on;
   // Enter, F3 and F12 all go back
write FOOTER;
exfmt LINCTL;

*inlr = *on;
return;
