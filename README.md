# Order Desk

A small IBM i order system written the way many shops still write them: RPG
programs with DDS display files and subfiles, sharing DDS physical files and
calling each other. It is the starting point of an article series that brings
it to the web, first with [Veneer](https://github.com/danlong005/Veneer)
without changing a line of RPG, then by rewriting one program with
[RPGAPI](https://github.com/danlong005/RPGAPI).

## What's in it

| Program | Display file | What it does |
| --- | --- | --- |
| `ODMENU` | `ODMENUD` | Main menu: options 1 to 4 and 90 (sign off), and a command line |
| `CUSTWRK` | `CUSTWRKD` | Work with Customers: by name, position-to, `2=Change 4=Delete 5=Display 7=Orders`, F6=Add, a delete confirmation window |
| `CUSTMNT` | `CUSTMNTD` | Add, change or display a customer, with checks on each field and a help window (Help key) |
| `CUSTSEL` | `CUSTSELD` | Window: pick a customer (F4 in order entry) |
| `ITEMSEL` | `ITEMSELD` | Window: pick an item (F4 in order entry, menu option 4) |
| `ORDENT` | `ORDENTD` | Order entry: header and up to 30 lines on one screen, priced as you go. F10 places the order, held if it goes over the customer's credit limit |
| `ORDWRK` | `ORDWRKD` | Work with Orders, newest first, by status and customer: `4=Cancel 5=Display 6=Release`, F6=New order |
| `ORDDSP` | `ORDDSPD` | Display an order and its lines |

| File | |
| --- | --- |
| `CUSTMAST` | Customers, by number |
| `CUSTNAME` | Logical: customers by name |
| `ITEMMAST` | Items |
| `ORDHDR` | Order headers |
| `ORDHCUST`, `ORDHSTAT` | Logicals: orders by customer and by status, newest first |
| `ORDDTL` | Order lines |
| `ODNEXTORD` | Data area: the next order number |

The source is in `qddssrc` (DDS) and `qrpglesrc` (free-form RPG), and
`sql/sample-data.sql` loads 40 customers, 25 items and four months of orders.

## Building it

On an IBM i with the ILE RPG compiler, such as [PUB400](https://pub400.com),
in a shell (SSH):

```bash
export PATH=/QOpenSys/pkgs/bin:$PATH     # GNU make, not the AIX one
git clone https://github.com/danlong005/OrderDesk.git
cd OrderDesk
make LIB=MYLIB           # the files, display files and programs
make data LIB=MYLIB      # the sample data
```

`MYLIB` is a library you already have (on PUB400, the one you were given).
The build creates `QDDSSRC` there for the DDS. It creates the data files only
when they are missing, so building again keeps your data. `make data` replaces
the data with the sample data. A compile that fails stops the build; its
listing is in your spooled files (`WRKSPLF`).

`make clean LIB=MYLIB` deletes the programs and display files. `make drop
LIB=MYLIB` deletes the data files too.

## Running it

From a 5250 session:

```
ADDLIBLE MYLIB
CALL ODMENU
```

Things to try:
- Option 1, then `5` next to a customer, and the Help key on its screen
- Option 2, F4 on the customer and on an item line, and Enter to price the
  lines. A large order for a customer with a small credit limit (such as
  1036, inactive, or 1028, $5,000) is refused or held
- Option 3, with `HELD` as the status: `6` releases an order, `5` shows it
