"""Writes Order Desk's DDS with every column in place, and checks the screens.

Usage: python3 tools/ddsgen.py .
"""
import os
import re
import sys

OUT = os.path.join(sys.argv[1], 'qddssrc')


def put(buf, col, text):
    for i, ch in enumerate(text):
        buf[col - 1 + i] = ch


def cond_text(ind):
    """['30'] or ['N30', '31'] -> columns 8-16."""
    out = ''
    for i in ind:
        out += i.rjust(3)
    return out


def dds_lines(ind=(), ntype='', name='', length='', dtype='', dec='', usage='',
              row='', col='', kw=''):
    """One DDS entry; a keyword longer than 36 characters continues with '-'."""
    buf = [' '] * 80
    put(buf, 6, 'A')
    if ind:
        put(buf, 8, cond_text(ind))
    if ntype:
        put(buf, 17, ntype)
    if name:
        put(buf, 19, name)
    if length != '':
        put(buf, 30, str(length).rjust(5))
    if dtype:
        put(buf, 35, dtype)
    if dec != '':
        put(buf, 36, str(dec).rjust(2))
    if usage:
        put(buf, 38, usage)
    if row != '':
        put(buf, 39, str(row).rjust(3))
    if col != '':
        put(buf, 42, str(col).rjust(3))
    lines = []
    while len(kw) > 36:
        # break after a blank: '-' continues the text at column 45 of the next line
        cut = kw.rfind(' ', 0, 35) + 1 or 35
        put(buf, 45, kw[:cut] + '-')
        lines.append(''.join(buf).rstrip())
        kw = kw[cut:]
        buf = [' '] * 80
        put(buf, 6, 'A')
    put(buf, 45, kw)
    lines.append(''.join(buf).rstrip())
    return lines


def comment(text):
    return ['     A*' + (' ' + text if text else '')]


class Source:
    def __init__(self, name, title):
        self.name = name
        self.lines = comment(title) + comment('')
        self.records = {}
        self.current = None

    def kw(self, kw, ind=()):
        self.lines += dds_lines(ind=ind, kw=kw)

    def comment(self, text):
        self.lines += comment(text)

    def record(self, name, *kws, ntype='R'):
        self.lines += dds_lines(ntype=ntype, name=name, kw=kws[0] if kws else '')
        for k in kws[1:]:
            self.kw(k)
        self.current = self.records.setdefault(name, [])

    def field(self, name, length, dtype='A', dec='', usage='', row='', col='', kws=(), ind=()):
        self.lines += dds_lines(ind=ind, name=name, length=length, dtype=dtype, dec=dec,
                                usage=usage, row=row, col=col)
        for k in kws:
            if isinstance(k, tuple):
                self.kw(k[1], ind=k[0])
            else:
                self.kw(k)
        if row != '':
            self.current.append((row, col, shown_length(length, dtype, dec, kws), name))

    def const(self, row, col, text, *kws, ind=()):
        assert "'" not in text
        self.lines += dds_lines(ind=ind, row=row, col=col, kw=f"'{text}'")
        for k in kws:
            self.kw(k)
        self.current.append((row, col, len(text), text))

    def special(self, row, col, kw, *kws, width):
        self.lines += dds_lines(row=row, col=col, kw=kw)
        for k in kws:
            self.kw(k)
        self.current.append((row, col, width, kw))

    def key(self, name, *kws):
        self.lines += dds_lines(ntype='K', name=name, kw=kws[0] if kws else '')

    def write(self, ext):
        path = os.path.join(OUT, f'{self.name}.{ext}')
        with open(path, 'w') as f:
            f.write('\n'.join(self.lines) + '\n')
        for line in self.lines:
            assert len(line) <= 80, (self.name, line)


def shown_length(length, dtype, dec, kws):
    """Characters a field takes on the screen, with its edit code."""
    if dtype not in ('S', 'Y'):
        return length
    code = next((re.match(r'EDTCDE\((.)\)', k).group(1) for k in kws
                 if isinstance(k, str) and k.startswith('EDTCDE')), None)
    dec = dec or 0
    if code in ('1', 'J'):
        whole = length - dec
        n = length + max(0, (whole - 1) // 3) + (1 if dec else 0)
        return n + (1 if code == 'J' else 0)
    if code == '3':
        return length + (1 if dec else 0)
    return length


def check_layout(src, groups):
    """Items on a row must not overlap, attribute bytes included."""
    for group in groups:
        items = [i for name in group for i in src.records[name]]
        by_row = {}
        for row, col, width, what in items:
            by_row.setdefault(row, []).append((col, col + width - 1, what))
        for row, spans in by_row.items():
            spans.sort()
            for (a0, a1, aw), (b0, b1, bw) in zip(spans, spans[1:]):
                # b's attribute byte is at b0-1, after a's end at a1
                if b0 - 1 <= a1:
                    raise SystemExit(f'{src.name} row {row}: {aw!r} ({a0}-{a1}) overlaps {bw!r} ({b0}-{b1})')
            for c0, c1, w in spans:
                if c0 < 2 or c1 > 79:
                    raise SystemExit(f'{src.name} row {row}: {w!r} ({c0}-{c1}) off the screen')


def header(s, program, title):
    """Row 1: program name, title in the middle (highlighted), system name; row 2: date."""
    s.const(1, 2, program)
    s.const(1, 41 - len(title) // 2, title, 'DSPATR(HI)')
    s.special(1, 71, 'SYSNAME', width=8)
    s.special(2, 71, 'DATE', 'EDTCDE(Y)', width=8)


def dspf(name, title):
    s = Source(name, title)
    s.kw('DSPSIZ(24 80 *DS3)')
    s.kw('INDARA')
    return s


# ---------------------------------------------------------------- files

def physical_files():
    s = Source('CUSTMAST', 'CUSTMAST: customers')
    s.kw('UNIQUE')
    s.record('CUSTR', "TEXT('Customer')")
    s.field('CMCUST', 6, 'S', 0, kws=["COLHDG('Customer' 'number')"])
    s.field('CMNAME', 40, kws=["COLHDG('Name')"])
    s.field('CMADDR', 40, kws=["COLHDG('Address')"])
    s.field('CMCITY', 25, kws=["COLHDG('City')"])
    s.field('CMSTATE', 2, kws=["COLHDG('State')"])
    s.field('CMZIP', 10, kws=["COLHDG('ZIP code')"])
    s.field('CMPHONE', 15, kws=["COLHDG('Phone')"])
    s.field('CMCRLMT', 9, 'P', 2, kws=["COLHDG('Credit' 'limit')"])
    s.field('CMACTV', 1, kws=["COLHDG('Active')", "TEXT('Y or N')"])
    s.field('CMADDED', 8, 'S', 0, kws=["COLHDG('Date' 'added')", "TEXT('YYYYMMDD')"])
    s.key('CMCUST')
    s.write('pf')

    s = Source('CUSTNAME', 'CUSTNAME: customers by name')
    s.record('CUSTR', 'PFILE(CUSTMAST)')
    s.key('CMNAME')
    s.key('CMCUST')
    s.write('lf')

    s = Source('ITEMMAST', 'ITEMMAST: items')
    s.kw('UNIQUE')
    s.record('ITEMR', "TEXT('Item')")
    s.field('IMITEM', 10, kws=["COLHDG('Item')"])
    s.field('IMDESC', 30, kws=["COLHDG('Description')"])
    s.field('IMPRICE', 7, 'P', 2, kws=["COLHDG('Price')"])
    s.field('IMONHND', 7, 'P', 0, kws=["COLHDG('On hand')"])
    s.field('IMUOM', 3, kws=["COLHDG('Unit')"])
    s.key('IMITEM')
    s.write('pf')

    s = Source('ORDHDR', 'ORDHDR: order headers')
    s.kw('UNIQUE')
    s.record('ORDHR', "TEXT('Order header')")
    s.field('OHORD', 7, 'S', 0, kws=["COLHDG('Order')"])
    s.field('OHCUST', 6, 'S', 0, kws=["COLHDG('Customer')"])
    s.field('OHDATE', 8, 'S', 0, kws=["COLHDG('Order' 'date')", "TEXT('YYYYMMDD')"])
    s.field('OHSHIP', 8, 'S', 0, kws=["COLHDG('Ship' 'date')", "TEXT('YYYYMMDD')"])
    s.field('OHSTAT', 10, kws=["COLHDG('Status')",
                               "TEXT('OPEN HELD SHIPPED CANCELLED')"])
    s.field('OHTOTAL', 11, 'P', 2, kws=["COLHDG('Total')"])
    s.field('OHPO', 20, kws=["COLHDG('Customer' 'PO')"])
    s.key('OHORD')
    s.write('pf')

    s = Source('ORDHCUST', 'ORDHCUST: orders by customer, newest first')
    s.record('ORDHR', 'PFILE(ORDHDR)')
    s.key('OHCUST')
    s.key('OHORD', 'DESCEND')
    s.write('lf')

    s = Source('ORDHSTAT', 'ORDHSTAT: orders by status, newest first')
    s.record('ORDHR', 'PFILE(ORDHDR)')
    s.key('OHSTAT')
    s.key('OHORD', 'DESCEND')
    s.write('lf')

    s = Source('ORDDTL', 'ORDDTL: order lines')
    s.kw('UNIQUE')
    s.record('ORDDR', "TEXT('Order line')")
    s.field('ODORD', 7, 'S', 0, kws=["COLHDG('Order')"])
    s.field('ODLINE', 3, 'S', 0, kws=["COLHDG('Line')"])
    s.field('ODITEM', 10, kws=["COLHDG('Item')"])
    s.field('ODQTY', 5, 'P', 0, kws=["COLHDG('Quantity')"])
    s.field('ODPRICE', 7, 'P', 2, kws=["COLHDG('Price')"])
    s.field('ODAMT', 9, 'P', 2, kws=["COLHDG('Amount')"])
    s.key('ODORD')
    s.key('ODLINE')
    s.write('pf')


# ---------------------------------------------------------------- screens

def odmenud():
    s = dspf('ODMENUD', 'ODMENUD: Order Desk main menu')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")
    s.record('MENU')
    header(s, 'ODMENU', 'Order Desk')
    s.const(3, 2, 'Select one of the following:')
    s.const(5, 6, '1. Work with customers')
    s.const(6, 6, '2. Enter an order')
    s.const(7, 6, '3. Work with orders')
    s.const(8, 6, '4. Browse items')
    s.const(10, 5, '90. Sign off')
    s.const(20, 2, 'Selection or command')
    s.const(21, 2, '===>')
    s.field('CMD', 72, usage='B', row=21, col=7, kws=['CHECK(LC)'])
    s.const(23, 2, 'F3=Exit   F12=Cancel', 'COLOR(BLU)')
    s.field('MSG', 78, usage='O', row=24, col=2, kws=['COLOR(WHT)'])
    s.write('dspf')
    check_layout(s, [['MENU']])


def custwrkd():
    s = dspf('CUSTWRKD', 'CUSTWRKD: Work with Customers')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")

    s.record('CUSTSFL', 'SFL')
    s.field('SOPT', 1, usage='B', row=9, col=3)
    s.field('SCUST', 6, 'S', 0, usage='O', row=9, col=7)
    s.field('SNAME', 30, usage='O', row=9, col=15)
    s.field('SCITY', 20, usage='O', row=9, col=47)
    s.field('SSTATE', 2, usage='O', row=9, col=69)
    s.field('SACTV', 1, usage='O', row=9, col=75)

    s.record('CUSTCTL', 'SFLCTL(CUSTSFL)', 'SFLSIZ(0100)', 'SFLPAG(0012)',
             "CF05(05 'Refresh')", "CF06(06 'Add')", 'OVERLAY')
    s.kw('SFLDSP', ind=['31'])
    s.kw('SFLDSPCTL', ind=['32'])
    s.kw('SFLCLR', ind=['33'])
    s.kw('SFLEND(*MORE)', ind=['34'])
    s.field('TOPRRN', 4, 'S', 0, usage='H', kws=['SFLRCDNBR(CURSOR)'])
    header(s, 'CUSTWRK', 'Work with Customers')
    s.const(3, 2, 'Position to name . . .')
    s.field('POSNAM', 20, usage='B', row=3, col=26, kws=['CHECK(LC)'])
    s.const(5, 2, 'Type options, press Enter.', 'COLOR(BLU)')
    s.const(6, 3, '2=Change   4=Delete   5=Display   7=Orders', 'COLOR(BLU)')
    for col, text in ((2, 'Opt'), (7, 'Number'), (15, 'Name'), (47, 'City'),
                      (69, 'St'), (73, 'Active')):
        s.const(8, col, text, 'COLOR(WHT)')

    # A subfile control record can't have anything below the subfile, so the
    # F-key legend and the message line are a record of their own, written first.
    s.record('FOOTER')
    s.const(23, 2, 'F3=Exit   F5=Refresh   F6=Add   F12=Cancel', 'COLOR(BLU)')
    s.field('MSG', 78, usage='O', row=24, col=2, kws=['COLOR(WHT)'])

    s.record('DLTWIN', 'WINDOW(6 15 8 48)', "WDWTITLE((*TEXT 'Delete Customer'))",
             "CA10(10 'Delete')")
    s.const(2, 2, 'Customer . . :')
    s.field('DCUST', 6, 'S', 0, usage='O', row=2, col=17)
    s.field('DNAME', 30, usage='O', row=3, col=17)
    s.const(5, 2, 'Press F10 to delete this customer.')
    s.const(7, 2, 'F10=Delete   F12=Cancel', 'COLOR(BLU)')
    s.write('dspf')
    check_layout(s, [['CUSTSFL', 'CUSTCTL', 'FOOTER'], ['DLTWIN']])


def custmntd():
    s = dspf('CUSTMNTD', 'CUSTMNTD: add, change or display a customer')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")

    s.record('DETAIL', 'HELP(25)')
    s.const(1, 2, 'CUSTMNT')
    s.field('TITLE', 28, usage='O', row=1, col=27, kws=['DSPATR(HI)'])
    s.special(1, 71, 'SYSNAME', width=8)
    s.special(2, 71, 'DATE', 'EDTCDE(Y)', width=8)
    s.const(3, 2, 'Type changes, press Enter.', 'COLOR(BLU)', ind=['N30'])

    s.const(5, 2, 'Customer number . . . . :')
    s.field('DCUST', 6, 'S', 0, usage='O', row=5, col=30)

    def entry(row, label, name, length, dtype='A', dec='', kws=(), err=None, hint=None):
        s.const(row, 2, label)
        k = list(kws) + [(['30'], 'DSPATR(PR)')]
        if err:
            k.append(([err[0]], f"ERRMSG('{err[1]}' {err[0]})"))
        s.field(name, length, dtype, dec, usage='B', row=row, col=30, kws=k)
        if hint:
            s.const(row, hint[0], hint[1], 'COLOR(BLU)')

    entry(6, 'Name  . . . . . . . . . .', 'DNAME', 40, kws=['CHECK(LC)'],
          err=('51', 'Type the customer name.'))
    entry(7, 'Address . . . . . . . . .', 'DADDR', 40, kws=['CHECK(LC)'])
    entry(8, 'City  . . . . . . . . . .', 'DCITY', 25, kws=['CHECK(LC)'],
          err=('52', 'Type the city.'))
    entry(9, 'State . . . . . . . . . .', 'DSTATE', 2,
          err=('53', 'Type a two-letter US state code, such as TX.'),
          hint=(34, 'Two letters, such as TX'))
    entry(10, 'ZIP code  . . . . . . . .', 'DZIP', 10)
    entry(11, 'Phone . . . . . . . . . .', 'DPHONE', 15)
    entry(12, 'Credit limit  . . . . . .', 'DCRLMT', 9, 'Y', 2, kws=['EDTCDE(1)'])
    entry(13, 'Active  . . . . . . . . .', 'DACTV', 1, kws=["VALUES('Y' 'N')"],
          hint=(34, 'Y=Yes, N=No'))
    entry(14, 'Date added  . . . . . . .', 'DADDED', 8, 'Y', 0,
          err=('54', 'Type a date as YYYYMMDD, such as 20261030.'),
          hint=(40, 'YYYYMMDD'))
    s.const(23, 2, 'F3=Exit   F12=Cancel', 'COLOR(BLU)')

    s.record('HLPWIN', 'WINDOW(4 8 14 62)', "WDWTITLE((*TEXT 'Customer Help'))")
    help_text = [
        'A customer is anyone who can place orders.',
        '',
        'Name, city and state are required. The state is',
        'the two-letter US postal code.',
        '',
        'Credit limit: orders that take the customer over',
        'it, with their open and held orders, are held',
        'for credit review when they are placed.',
        '',
        'Active: only active customers can place orders.',
    ]
    for i, text in enumerate(help_text, start=2):
        if text:
            s.const(i, 2, text)
    s.const(13, 2, 'Enter=Continue   F12=Cancel', 'COLOR(BLU)')
    s.write('dspf')
    check_layout(s, [['DETAIL'], ['HLPWIN']])


def selection_window(name, title, program_title, columns, key_label, key_field, key_length,
                     window, lowercase):
    """CUSTSELD / ITEMSELD: a subfile in a window, 1=Select, position-to."""
    s = dspf(name, program_title)
    s.kw("CA12(12 'Cancel')")
    # The window, with its border, title and F-key legend, is a record of its
    # own, since a subfile control record can't have anything below the subfile.
    s.record('SELWIN', window, f"WDWTITLE((*TEXT '{title}'))")
    # (line 15, the window's last, is its message line)
    s.const(14, 2, 'F12=Cancel', 'COLOR(BLU)')
    s.record('SELSFL', 'SFL')
    s.field('SOPT', 1, usage='B', row=5, col=3)
    for f in columns:
        s.field(f['name'], f['length'], f.get('type', 'A'), f.get('dec', ''), usage='O',
                row=5, col=f['col'], kws=f.get('kws', ()))
    s.record('SELCTL', 'SFLCTL(SELSFL)', 'SFLSIZ(0050)', 'SFLPAG(0008)', 'WINDOW(SELWIN)',
             'OVERLAY')
    s.kw('SFLDSP', ind=['31'])
    s.kw('SFLDSPCTL', ind=['32'])
    s.kw('SFLCLR', ind=['33'])
    s.kw('SFLEND(*MORE)', ind=['34'])
    s.const(1, 2, key_label)
    s.field(key_field, key_length, usage='B', row=1, col=18, kws=['CHECK(LC)'] if lowercase else ())
    s.const(2, 2, 'Type 1 to select, press Enter.', 'COLOR(BLU)')
    s.const(4, 2, 'Opt', 'COLOR(WHT)')
    for f in columns:
        s.const(4, f.get('head_col', f['col']), f['head'], 'COLOR(WHT)')
    s.write('dspf')
    check_layout(s, [['SELSFL', 'SELCTL', 'SELWIN']])


def custseld():
    selection_window(
        'CUSTSELD', 'Select Customer', 'CUSTSELD: pick a customer (window)',
        [dict(name='SCUST', length=6, type='S', dec=0, col=7, head='Number'),
         dict(name='SNAME', length=30, col=15, head='Name')],
        'Position to . .', 'SPOS', 20, 'WINDOW(3 18 15 46)', True)


def itemseld():
    selection_window(
        'ITEMSELD', 'Select Item', 'ITEMSELD: pick an item (window)',
        [dict(name='SITEM', length=10, col=7, head='Item'),
         dict(name='SDESC', length=25, col=19, head='Description'),
         dict(name='SPRICE', length=7, type='Y', dec=2, col=46, kws=['EDTCDE(1)'],
              head='Price', head_col=50),
         dict(name='SONHND', length=7, type='Y', dec=0, col=57, kws=['EDTCDE(1)'],
              head='On hand', head_col=59)],
        'Position to . .', 'SPOS', 10, 'WINDOW(3 6 15 66)', False)


def ordentd():
    s = dspf('ORDENTD', 'ORDENTD: order entry')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")

    s.record('ORDSFL', 'SFL')
    s.field('SLINE', 2, 'S', 0, usage='O', row=11, col=2)
    s.field('SITEM', 10, usage='B', row=11, col=6, kws=[(['61'], 'DSPATR(RI PC)')])
    s.field('SQTY', 5, 'Y', 0, usage='B', row=11, col=18,
            kws=['EDTCDE(Z)', (['62'], 'DSPATR(RI PC)')])
    s.field('SDESC', 30, usage='O', row=11, col=25)
    s.field('SPRICE', 7, 'Y', 2, usage='O', row=11, col=57, kws=['EDTCDE(1)'])
    s.field('SAMT', 9, 'Y', 2, usage='O', row=11, col=68, kws=['EDTCDE(1)'])

    s.record('ORDCTL', 'SFLCTL(ORDSFL)', 'SFLSIZ(0030)', 'SFLPAG(0010)',
             "CF04(04 'Prompt')", "CF05(05 'Clear')", "CF10(10 'Place order')",
             'RTNCSRLOC(&CSRRCD &CSRFLD)', 'SFLCSRRRN(&CSRRRN)', 'OVERLAY')
    s.kw('SFLDSP', ind=['31'])
    s.kw('SFLDSPCTL', ind=['32'])
    s.kw('SFLCLR', ind=['33'])
    s.kw('SFLEND(*MORE)', ind=['34'])
    s.field('TOPRRN', 4, 'S', 0, usage='H', kws=['SFLRCDNBR(CURSOR)'])
    s.field('CSRRCD', 10, usage='H')
    s.field('CSRFLD', 10, usage='H')
    s.field('CSRRRN', 5, 'S', 0, usage='H')
    header(s, 'ORDENT', 'Order Entry')
    s.const(3, 2, 'Customer . . . . . . .')
    s.field('HCUST', 6, 'Y', 0, usage='B', row=3, col=26,
            kws=['EDTCDE(Z)',
                 (['51'], "ERRMSG('Type an active customer number, or press F4 to pick one.' 51)")])
    s.field('HCNAME', 30, usage='O', row=3, col=35)
    s.const(4, 2, 'Customer PO  . . . . .')
    s.field('HPO', 20, usage='B', row=4, col=26)
    s.const(5, 2, 'Ship date  . . . . . .')
    s.field('HSHIP', 8, 'Y', 0, usage='B', row=5, col=26,
            kws=['EDTCDE(Z)',
                 (['52'], "ERRMSG('Type a ship date from today on, as YYYYMMDD.' 52)")])
    s.const(5, 35, 'YYYYMMDD, blank for a week from today', 'COLOR(BLU)')
    s.const(6, 2, 'Credit limit . . . . :')
    s.field('HCRLMT', 9, 'Y', 2, usage='O', row=6, col=26, kws=['EDTCDE(1)'])
    s.const(8, 2, 'Type items and quantities, press Enter to check them.', 'COLOR(BLU)')
    for col, text in ((2, 'Ln'), (6, 'Item'), (18, 'Qty'), (25, 'Description'),
                      (61, 'Price'), (74, 'Amount')):
        s.const(10, col, text, 'COLOR(WHT)')

    # Below the subfile: a record of its own (see CUSTWRKD)
    s.record('FOOTER')
    s.const(22, 45, 'Order total . . . :')
    s.field('HTOTAL', 11, 'Y', 2, usage='O', row=22, col=65, kws=['EDTCDE(1)'])
    s.const(23, 2, 'F3=Exit   F4=Prompt   F5=Clear   F10=Place order   F12=Cancel',
            'COLOR(BLU)')
    s.field('MSG', 78, usage='O', row=24, col=2, kws=['COLOR(WHT)'])
    s.write('dspf')
    check_layout(s, [['ORDSFL', 'ORDCTL', 'FOOTER']])


def ordwrkd():
    s = dspf('ORDWRKD', 'ORDWRKD: Work with Orders')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")

    s.record('ORDSFL', 'SFL')
    s.field('SOPT', 1, usage='B', row=10, col=3)
    s.field('SORD', 7, 'S', 0, usage='O', row=10, col=7)
    s.field('SDATE', 10, usage='O', row=10, col=16)
    s.field('SCNAME', 25, usage='O', row=10, col=28)
    s.field('SSTAT', 10, usage='O', row=10, col=55)
    s.field('SAMT', 9, 'Y', 2, usage='O', row=10, col=67, kws=['EDTCDE(1)'])

    s.record('ORDCTL', 'SFLCTL(ORDSFL)', 'SFLSIZ(0100)', 'SFLPAG(0011)',
             "CF05(05 'Refresh')", "CF06(06 'New order')", 'OVERLAY')
    s.kw('SFLDSP', ind=['31'])
    s.kw('SFLDSPCTL', ind=['32'])
    s.kw('SFLCLR', ind=['33'])
    s.kw('SFLEND(*MORE)', ind=['34'])
    s.field('TOPRRN', 4, 'S', 0, usage='H', kws=['SFLRCDNBR(CURSOR)'])
    header(s, 'ORDWRK', 'Work with Orders')
    s.const(3, 2, 'Status . . . . . . . .')
    s.field('FSTAT', 10, usage='B', row=3, col=26)
    s.const(3, 38, 'OPEN, HELD, SHIPPED, CANCELLED', 'COLOR(BLU)')
    s.const(4, 2, 'Customer . . . . . . .')
    s.field('FCUST', 6, 'Y', 0, usage='B', row=4, col=26, kws=['EDTCDE(Z)'])
    s.field('FCNAME', 30, usage='O', row=4, col=35)
    s.const(6, 2, 'Type options, press Enter.', 'COLOR(BLU)')
    s.const(7, 3, '4=Cancel   5=Display   6=Release', 'COLOR(BLU)')
    for col, text in ((2, 'Opt'), (7, 'Order'), (16, 'Date'), (28, 'Customer'),
                      (55, 'Status'), (73, 'Amount')):
        s.const(9, col, text, 'COLOR(WHT)')

    # Below the subfile: a record of its own (see CUSTWRKD)
    s.record('FOOTER')
    s.const(23, 2, 'F3=Exit   F5=Refresh   F6=New order   F12=Cancel', 'COLOR(BLU)')
    s.field('MSG', 78, usage='O', row=24, col=2, kws=['COLOR(WHT)'])
    s.write('dspf')
    check_layout(s, [['ORDSFL', 'ORDCTL', 'FOOTER']])


def orddspd():
    s = dspf('ORDDSPD', 'ORDDSPD: display an order')
    s.kw("CA03(03 'Exit')")
    s.kw("CA12(12 'Cancel')")

    s.record('LINSFL', 'SFL')
    s.field('SLINE', 3, 'S', 0, usage='O', row=11, col=2)
    s.field('SITEM', 10, usage='O', row=11, col=7)
    s.field('SDESC', 30, usage='O', row=11, col=19)
    s.field('SQTY', 5, 'Y', 0, usage='O', row=11, col=50, kws=['EDTCDE(1)'])
    s.field('SPRICE', 7, 'Y', 2, usage='O', row=11, col=57, kws=['EDTCDE(1)'])
    s.field('SAMT', 9, 'Y', 2, usage='O', row=11, col=67, kws=['EDTCDE(1)'])

    s.record('LINCTL', 'SFLCTL(LINSFL)', 'SFLSIZ(0100)', 'SFLPAG(0009)', 'OVERLAY')
    s.kw('SFLDSP', ind=['31'])
    s.kw('SFLDSPCTL', ind=['32'])
    s.kw('SFLCLR', ind=['33'])
    s.kw('SFLEND(*MORE)', ind=['34'])
    header(s, 'ORDDSP', 'Display Order')
    s.const(3, 2, 'Order  . . . . . . . :')
    s.field('DORD', 7, 'S', 0, usage='O', row=3, col=26)
    s.const(3, 45, 'Status  . . :')
    s.field('DSTAT', 10, usage='O', row=3, col=60, kws=['DSPATR(HI)'])
    s.const(4, 2, 'Customer . . . . . . :')
    s.field('DCUST', 6, 'S', 0, usage='O', row=4, col=26)
    s.field('DCNAME', 30, usage='O', row=4, col=35)
    s.const(5, 2, 'City . . . . . . . . :')
    s.field('DCITY', 25, usage='O', row=5, col=26)
    s.field('DSTATE', 2, usage='O', row=5, col=53)
    s.const(6, 2, 'Customer PO  . . . . :')
    s.field('DPO', 20, usage='O', row=6, col=26)
    s.const(7, 2, 'Order date . . . . . :')
    s.field('DDATE', 10, usage='O', row=7, col=26)
    s.const(7, 45, 'Ship date . :')
    s.field('DSHIP', 10, usage='O', row=7, col=60)
    for col, text in ((2, 'Ln'), (7, 'Item'), (19, 'Description'), (53, 'Qty'),
                      (61, 'Price'), (73, 'Amount')):
        s.const(10, col, text, 'COLOR(WHT)')

    # Below the subfile: a record of its own (see CUSTWRKD)
    s.record('FOOTER')
    s.const(21, 45, 'Order total . :')
    s.field('DTOTAL', 11, 'Y', 2, usage='O', row=21, col=62, kws=['EDTCDE(1)'])
    s.const(23, 2, 'F3=Exit   F12=Cancel', 'COLOR(BLU)')
    s.write('dspf')
    check_layout(s, [['LINSFL', 'LINCTL', 'FOOTER']])


os.makedirs(OUT, exist_ok=True)
physical_files()
odmenud()
custwrkd()
custmntd()
custseld()
itemseld()
ordentd()
ordwrkd()
orddspd()
print('ok')
