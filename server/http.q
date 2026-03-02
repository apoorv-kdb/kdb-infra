/ server/http.q
/ Minimal KDB+ 4.x HTTP routing layer.
/ Routes registered via .http.addRoute.
/ GET  handled by .z.ph
/ POST handled by .z.pp — KDB+ passes "path {json}" as x[0], headers as x[1]

.http.routes:()!()

.http.addRoute:{[method; path; fn]
  .http.routes[`$((string method),path)]:fn;
 }

/ ============================================================================
/ GET HANDLER
/ ============================================================================

.z.ph:{[x]
  pathStr:$[0h=type x; x 0; x];
  path:"/",$[10h=type pathStr; pathStr; ""];
  path:first "?" vs path;
  rk:`$(("GET"),path);
  if[not rk in key .http.routes;
    :"HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n{\"error\":\"not found: ",path,"\"}"
    ];
  fn:.http.routes rk;
  res:@[fn; ()!(); {"ERROR: ",x}];
  if[10h=type res;
    :"HTTP/1.1 500 Error\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n{\"error\":\"",res,"\"}"
    ];
  body:.j.j res;
  "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n\r\n",body
 }

/ ============================================================================
/ POST HANDLER
/ ============================================================================
/ KDB+ 4.x passes POST as a 2-element list: x[0] = "path {json body}", x[1] = headers dict
/ Must split x[0] on first space to separate the path from the JSON body.
/ _route is embedded in the JSON body by the frontend for routing.
/ Note: `_route in KDB+ parses as delete operator — must use `$"_route" instead.

.z.pp:{[x]
  / Extract raw string — first element if list, else use directly
  raw:$[0h=type x; x 0; x];
  raw:$[10h=type raw; raw; ""];

  / Split "path {json body}" on first space
  spaceIdx:first where raw=" ";
  body:$[null spaceIdx; ""; (spaceIdx+1)_raw];

  / Parse JSON body — fall back to empty dict on parse failure
  params:@[.j.k; body; {()!()}];

  / Extract route from _route key in body
  / Cannot use `_route — underscore prefix is the delete operator in q
  routeKey:`$"_route";
  path:$[routeKey in key params; string params routeKey; "/unknown"];
  params _:routeKey;

  rk:`$(("POST"),path);
  if[not rk in key .http.routes;
    :"HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n{\"error\":\"not found: ",path,"\"}"
    ];

  fn:.http.routes rk;
  res:@[fn; params; {"ERROR: ",x}];

  if[10h=type res;
    :"HTTP/1.1 500 Error\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n{\"error\":\"",res,"\"}"
    ];

  body:.j.j res;
  "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n\r\n",body
 }

.http.ok:{[data] data}
.http.err:{[code; msg] '`$msg}

show "  http.q loaded"
