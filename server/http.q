/ http.q
/ Generic HTTP layer for kdb+ app servers
/ Sets .z.ph — do not define .z.ph elsewhere after loading this file
/
/ Usage:
/   1. \l server/http.q                       (done via server_init.q)
/   2. .http.addRoute[`GET;  "/path"; fn]     (in server.q)
/   3. .http.addRoute[`POST; "/path"; fn]
/
/ Handler functions receive a single dict of parsed JSON params (GET: empty dict).
/ They return any q value — it gets .j.j serialised as the response body.
/ Throw a signal to return a JSON error response instead.
/
/ Dependencies: none

/ ============================================================================
/ ROUTE TABLE
/ ============================================================================

.http.routes:(`symbol$())!()

.http.addRoute:{[method; path; fn]
  if[not method in key .http.routes; .http.routes[method]:()!()];
  .http.routes[method][path]:fn;
 }

/ ============================================================================
/ REQUEST PARSING
/ ============================================================================

.http._method:{[raw] `$first " " vs first "\r\n" vs raw}

.http._path:{[raw] first "?" vs 1 (" " vs first "\r\n" vs raw)}

.http._body:{[raw]
  parts:"\r\n\r\n" vs raw;
  $[1 < count parts; last parts; ""]
 }

.http._parseBody:{[raw]
  body:.http._body raw;
  $[0 = count body; ()!(); @[.j.k; body; {()!()}]]
 }

/ ============================================================================
/ RESPONSE BUILDING
/ ============================================================================

.http._cors:
  "Access-Control-Allow-Origin: *\r\n",
  "Access-Control-Allow-Methods: POST, GET, OPTIONS\r\n",
  "Access-Control-Allow-Headers: Content-Type\r\n"

.http._respond:{[code; text; body]
  "HTTP/1.1 ",string[code]," ",text,"\r\n",
  "Content-Type: application/json\r\n",
  .http._cors,"\r\n",
  body
 }

.http.ok:{[data]  .http._respond[200; "OK";    .j.j data]}
.http.err:{[code; msg] .http._respond[code; "Error"; .j.j `error`message!(code; msg)]}

/ ============================================================================
/ DISPATCH
/ ============================================================================

.http._dispatch:{[method; path; raw]
  if[not method in key .http.routes; :.http.err[405; "Method not allowed: ",string method]];
  paths:.http.routes method;
  if[not path in key paths;       :.http.err[404; "Not found: ",path]];

  params:$[method=`POST; .http._parseBody raw; ()!()];

  result:.[paths path; enlist params; {`__err`msg!(1b; x)}];
  $[`__err in key result; .http.err[500; string result`msg]; .http.ok result]
 }

/ ============================================================================
/ .z.ph
/ ============================================================================

.z.ph:{[raw]
  method:.http._method raw;
  path:.http._path raw;

  if[method=`OPTIONS;
    :"HTTP/1.1 204 No Content\r\n",
     .http._cors,
     "Access-Control-Max-Age: 86400\r\n\r\n"];

  .http._dispatch[method; path; raw]
 }

show "  http.q loaded"
