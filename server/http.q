/ http.q — minimal kdb+ 4.x HTTP layer

.http.routes:()!()

.http.addRoute:{[method; path; fn]
  .http.routes[`$((string method),path)]:fn;
 }

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

.z.pp:{[x]
  bodyStr:$[0h=type x; x 0; x];
  body:$[10h=type bodyStr; bodyStr; ""];
  params:@[.j.k; body; {()!()}];
  path:$[`_route in key params; string params`_route; "/unknown"];
  params _:`_route;
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
