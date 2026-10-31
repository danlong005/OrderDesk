# Order Desk: build the files, display files and programs into LIB.
#
#   make LIB=MYLIB          build everything (data files only if missing)
#   make data LIB=MYLIB     load the sample data, replacing what is there
#   make clean LIB=MYLIB    delete the programs and display files
#   make drop LIB=MYLIB     delete everything, data files and data included
#
# LIB must already exist: on PUB400, use the library you were given.

LIB ?=
# Absolute IFS path of this checkout: by default the directory make runs in.
IFS_PATH ?= $(CURDIR)
# CCSID of LIB/QDDSSRC when the build creates it.
SRC_CCSID ?= 37

PHYSICAL = CUSTMAST ITEMMAST ORDHDR ORDDTL
LOGICAL = CUSTNAME ORDHCUST ORDHSTAT
DISPLAYS = ODMENUD CUSTWRKD CUSTMNTD CUSTSELD ITEMSELD ORDENTD ORDWRKD ORDDSPD
PROGRAMS = odmenu custwrk custmnt custsel itemsel ordent ordwrk orddsp

SHELL = /QOpenSys/usr/bin/qsh

# Copies qddssrc/$$name.$$type into member $$name of LIB/QDDSSRC.
COPY_MEMBER = system "CPYFRMSTMF FROMSTMF('$(IFS_PATH)/qddssrc/$$name.$$type') TOMBR('/QSYS.LIB/$(LIB).LIB/QDDSSRC.FILE/$$name.MBR') MBROPT(*REPLACE)" && \
  system "CHGPFM FILE($(LIB)/QDDSSRC) MBR($$name) SRCTYPE($$type) TEXT('Order Desk')"

.PHONY: all check files displays programs data clean drop

all: files displays programs

check:
	@test -n "$(LIB)" || { echo "Name the library to build into:  make LIB=MYLIB"; exit 1; }
	@system "CHKOBJ OBJ(QSYS/$(LIB)) OBJTYPE(*LIB)" >/dev/null 2>&1 || { \
	  echo "Library $(LIB) does not exist. Build into one you have:  make LIB=MYLIB"; exit 1; }
	@system "CHKOBJ OBJ($(LIB)/QDDSSRC) OBJTYPE(*FILE)" >/dev/null 2>&1 || \
	  system "CRTSRCPF FILE($(LIB)/QDDSSRC) RCDLEN(92) CCSID($(SRC_CCSID)) TEXT('Order Desk DDS')"
	@system "CHGATR OBJ('$(IFS_PATH)/qddssrc/*') ATR(*CCSID) VALUE(1252)"
	@system "CHGATR OBJ('$(IFS_PATH)/qrpglesrc/*') ATR(*CCSID) VALUE(1252)"
	@system "CHGATR OBJ('$(IFS_PATH)/sql/*') ATR(*CCSID) VALUE(1252)"

# Data files are created once and then left alone, so a rebuild keeps the data.
files: check
	@type=pf; for name in $(PHYSICAL); do \
	  if system "CHKOBJ OBJ($(LIB)/$$name) OBJTYPE(*FILE)" >/dev/null 2>&1; then \
	    echo "$$name exists, kept"; continue; fi; \
	  $(COPY_MEMBER) && \
	  system "CRTPF FILE($(LIB)/$$name) SRCFILE($(LIB)/QDDSSRC) SRCMBR($$name)" || exit 1; \
	done
	@type=lf; for name in $(LOGICAL); do \
	  if system "CHKOBJ OBJ($(LIB)/$$name) OBJTYPE(*FILE)" >/dev/null 2>&1; then \
	    echo "$$name exists, kept"; continue; fi; \
	  $(COPY_MEMBER) && \
	  system "CRTLF FILE($(LIB)/$$name) SRCFILE($(LIB)/QDDSSRC) SRCMBR($$name)" || exit 1; \
	done
	@system "CHKOBJ OBJ($(LIB)/ODNEXTORD) OBJTYPE(*DTAARA)" >/dev/null 2>&1 || \
	  system "CRTDTAARA DTAARA($(LIB)/ODNEXTORD) TYPE(*DEC) LEN(7 0) VALUE(0) TEXT('Order Desk: next order number')"

displays: check
	@type=dspf; for name in $(DISPLAYS); do \
	  $(COPY_MEMBER) || exit 1; \
	  system "DLTF FILE($(LIB)/$$name)" >/dev/null 2>&1; \
	  system "CRTDSPF FILE($(LIB)/$$name) SRCFILE($(LIB)/QDDSSRC) SRCMBR($$name)" || exit 1; \
	done

# The programs find the files and each other in the library list, at compile
# time as when they run. liblist fails when LIB is already there, which is fine.
programs: check
	@{ liblist -a $(LIB) >/dev/null 2>&1 || true; } && \
	for name in $(PROGRAMS); do \
	  system "CRTBNDRPG PGM($(LIB)/$$name) SRCSTMF('$(IFS_PATH)/qrpglesrc/$$name.rpgle') DBGVIEW(*SOURCE) TGTCCSID(*JOB) REPLACE(*YES)" || exit 1; \
	done

data: files
	system "RUNSQLSTM SRCSTMF('$(IFS_PATH)/sql/sample-data.sql') COMMIT(*NONE) NAMING(*SYS) DFTRDBCOL($(LIB))"
	system "CHGDTAARA DTAARA($(LIB)/ODNEXTORD) VALUE(0)"

clean: check
	-@for name in $(PROGRAMS); do system "DLTPGM PGM($(LIB)/$$name)"; done
	-@for name in $(DISPLAYS); do system "DLTF FILE($(LIB)/$$name)"; done

drop: clean
	-@for name in $(LOGICAL) $(PHYSICAL) QDDSSRC; do system "DLTF FILE($(LIB)/$$name)"; done
	-@system "DLTDTAARA DTAARA($(LIB)/ODNEXTORD)"
