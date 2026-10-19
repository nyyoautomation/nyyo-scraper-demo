#!/usr/bin/env python3
"""Local fixture shop for the kit test (no internet needed).

    python3 tests/fixture_server.py PORT LOGFILE

/robots.txt forbids /private/. /shop/page-2.html answers 429 (Retry-After: 1) the first time.
Page 2 repeats one product of page 1, so 25 items -> 24 unique rows. /js/ builds its items with JavaScript.
Every request is logged as one JSON line: time, path, status, user-agent.
"""
import json, sys, threading, time
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PRODUCTS = [  # sku, name, price text, rating word ('' = no rating), in stock
    ("SKU-001", "Espresso cups (set of 4)", "$12.50", "Four", True),
    ("SKU-002", "Café grinder, hand crank", "$1,299.00", "Five", True),
    ("SKU-003", "Pour-over kettle", "USD 45", "Three", False),
    ("SKU-004", "Paper filters x100", "$3.99", "", True),
    ("SKU-005", "Cold brew jar 1 L", "$19.00", "Two", True),
    ("SKU-006", "Milk frother", "$24.95", "Four", False),
    ("SKU-007", "Tamper 58 mm", "$29.00", "Five", True),
    ("SKU-008", "Knock box", "$15.00", "One", True),
    ("SKU-009", "Scale 0.1 g", "$34.99", "Four", True),
    ("SKU-010", "Travel mug \"Atlas\"", "$18.00", "Three", True),
    ("SKU-011", "Green tea sampler", "$9.50", "Four", True),
    ("SKU-012", "Matcha whisk", "$11.00", "Five", False),
    ("SKU-013", "Teapot, cast iron", "$59.00", "Four", True),
    ("SKU-014", "Loose-leaf infuser", "$6.75", "Three", True),
    ("SKU-015", "Chai spice mix", "$7.20", "Two", True),
    ("SKU-016", "Honey dipper", "$4.00", "", True),
    ("SKU-017", "Glass tumbler x2", "$14.00", "Four", True),
    ("SKU-018", "Coffee beans 1 kg", "$32.00", "Five", True),
    ("SKU-019", "Decaf beans 500 g", "$16.50", "Three", False),
    ("SKU-020", "Cleaning tablets", "$8.99", "Four", True),
    ("SKU-021", "Descaler 500 ml", "$10.00", "Three", True),
    ("SKU-022", "Barista apron", "$27.00", "Five", True),
    ("SKU-023", "Latte art pen", "$5.50", "Two", True),
    ("SKU-024", "Gift card 50", "$50.00", "", True),
]
PAGES = {1: PRODUCTS[0:10], 2: [PRODUCTS[3]] + PRODUCTS[10:19], 3: PRODUCTS[19:24]}


def card(p):
    sku, name, price, rating, stock = p
    r = f'<p class="stars {rating}">rated</p>' if rating else ""
    s = '<span class="stock in">In stock</span>' if stock else '<span class="stock out">Sold out</span>'
    return (f'<li class="product" data-sku="{sku}"><a class="name" href="/shop/item/{sku.lower()}.html" '
            f'title="{escape(name)}">{escape(name)}</a><span class="price">{escape(price)}</span>{r}{s}</li>')


def page(n):
    nxt = f'<a class="next" href="page-{n + 1}.html">next</a>' if n + 1 in PAGES else ""
    return (f'<!doctype html><html><head><meta charset="utf-8"><title>Fixture shop p{n}</title></head><body>'
            f'<ul class="grid">{"".join(card(p) for p in PAGES[n])}</ul><nav>{nxt}</nav></body></html>')


JS_PAGE = ('<!doctype html><html><head><meta charset="utf-8"></head><body><ul class="grid"></ul><script>'
           'const data=' + json.dumps([[p[0], p[1], p[2]] for p in PRODUCTS[:6]]) + ';setTimeout(()=>{'
           'document.querySelector(".grid").innerHTML=data.map(d=>`<li class="product" data-sku="${d[0]}">'
           '<a class="name" href="/shop/item/${d[0].toLowerCase()}.html" title="${d[1]}">${d[1]}</a>'
           '<span class="price">${d[2]}</span></li>`).join("")},300);</script></body></html>')


class H(BaseHTTPRequestHandler):
    hits = {}
    lock = threading.Lock()

    def do_GET(self):
        path = self.path.split("?")[0]
        with self.lock:
            H.hits[path] = H.hits.get(path, 0) + 1
            n = H.hits[path]
        status, body, ctype, extra = 404, "not found", "text/plain", {}
        if path == "/robots.txt":
            status, body = 200, "User-agent: *\nDisallow: /private/\n"
        elif path in ("/shop/", "/shop/index.html"):
            status, body, ctype = 200, page(1), "text/html; charset=utf-8"
        elif path == "/shop/page-2.html" and n == 1:
            status, body, extra = 429, "slow down", {"Retry-After": "1"}
        elif path.startswith("/shop/page-") and path[11:-5].isdigit() and int(path[11:-5]) in PAGES:
            status, body, ctype = 200, page(int(path[11:-5])), "text/html; charset=utf-8"
        elif path.startswith("/private/"):
            status, body, ctype = 200, page(1), "text/html; charset=utf-8"
        elif path in ("/js/", "/js/index.html"):
            status, body, ctype = 200, JS_PAGE, "text/html; charset=utf-8"
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        for k, v in extra.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"t": time.time(), "path": path, "status": status,
                                 "ua": self.headers.get("User-Agent", "")}) + "\n")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    PORT, LOG = int(sys.argv[1]), sys.argv[2]
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
