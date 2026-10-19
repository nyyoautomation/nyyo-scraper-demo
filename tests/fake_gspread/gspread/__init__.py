"""Stand-in for the gspread library, used only by tests/run_kit_test.sh (no Google account needed).
Records every call to $FAKE_GSPREAD_LOG so the test can check what the kit would send to Google."""
import json, os


class exceptions:  # same names the kit catches
    class APIError(Exception): pass
    class SpreadsheetNotFound(Exception): pass
    class WorksheetNotFound(Exception): pass


def _log(**kw):
    with open(os.environ["FAKE_GSPREAD_LOG"], "a", encoding="utf-8") as fh:
        fh.write(json.dumps(kw, ensure_ascii=False) + "\n")


class _WS:
    def __init__(self, title): self.title = title
    def clear(self): _log(call="clear", tab=self.title)
    def update(self, values=None, range_name=None): _log(call="update", tab=self.title, range=range_name, values=values)


class _SH:
    tabs = set()
    def worksheet(self, title):
        if title not in self.tabs: raise exceptions.WorksheetNotFound(title)
        return _WS(title)
    def add_worksheet(self, title, rows, cols):
        _log(call="add_worksheet", tab=title, rows=rows, cols=cols); self.tabs.add(title); return _WS(title)


class _GC:
    def open_by_key(self, key): _log(call="open_by_key", key=key); return _SH()


def service_account(filename):
    _log(call="service_account", file=os.path.basename(filename)); return _GC()
