**free
// ODMENU: the Order Desk main menu. A number calls one of the programs;
// anything else typed on the command line runs as a CL command.

ctl-opt dftactgrp(*no) actgrp('ORDDESK') option(*srcstmt:*nodebugio);

dcl-f ODMENUD workstn indds(keys);

dcl-ds keys len(99);
   exitKey ind pos(3);
   cancelKey ind pos(12);
end-ds;

dcl-pr CUSTWRK extpgm('CUSTWRK');
end-pr;
dcl-pr ORDENT extpgm('ORDENT');
end-pr;
dcl-pr ORDWRK extpgm('ORDWRK');
   customer zoned(6:0) const;
end-pr;
dcl-pr ITEMSEL extpgm('ITEMSEL');
   item char(10);
end-pr;
dcl-pr QCMDEXC extpgm('QCMDEXC');
   command char(3000) const;
   length packed(15:5) const;
end-pr;

   // the message of the last error, for a command that fails
dcl-ds status psds;
   messageId char(7) pos(40);
end-ds;

dcl-s selection varchar(72);
dcl-s item char(10);

dow *on;
   exfmt MENU;
   MSG = '';
   if exitKey or cancelKey;
      leave;
   endif;

   selection = %trim(CMD);
   CMD = '';
   select;
   when selection = '';
   when selection = '1';
      CUSTWRK();
   when selection = '2';
      ORDENT();
   when selection = '3';
      ORDWRK(0);
   when selection = '4';
      ITEMSEL(item);
   when selection = '90';
      runCommand('SIGNOFF');
   other;
      runCommand(selection);
   endsl;
enddo;

*inlr = *on;
return;


dcl-proc runCommand;
   dcl-pi *n;
      command varchar(72) const;
   end-pi;

   monitor;
      QCMDEXC(command : %len(command));
   on-error;
      MSG = 'Command ' + %trim(command) + ' ended in error (' + messageId
          + '). See the job log.';
   endmon;
end-proc;
