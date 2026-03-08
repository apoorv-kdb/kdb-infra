/ lib/discovery.q
/ Standalone file discovery module.
/ Resolves source configs to (source; refreshUnit; date; filepath) work items.
//
/ Two discovery strategies, selected by `dateFrom` column in source config:
//
/   dateFrom:`folder
/     Each subdirectory of `directory` whose name parses as a date is a candidate.
/     Files matching filePattern inside that subdir are the work items.
/     Subdir names are parsed using dateFormat.
//
/   dateFrom:`filename
/     Files matching filePattern directly inside `directory` are candidates.
/     Each filename is stripped of its extension, split by dateDelim,
/     and every token is tested against dateFormat. First valid parse wins.
//
/ Supported dateFormat values: yyyymmdd  yyyy.mm.dd  yyyy-mm-dd
//
/ Entry point:
/   .discovery.identifyWork[sourceConfig]
/     sourceConfig - table: source, refreshUnit, filePattern, dateFrom,
/                           dateFormat, dateDelim, delimiter, required, directory
/     Returns table: source, refreshUnit, date, filepath

/ ============================================================================
/ DATE PARSING
/ ============================================================================

/ Try to parse a single string token as a date using the given format.
/ Returns the parsed date or 0Nd if the token doesn't match the format.
.discovery.parseToken:{[fmt; token]
  n:count token;
  $[fmt~"yyyymmdd";
      [if[8 <> n; :0Nd];
       if[not all token in "0123456789"; :0Nd];
       @["D"$; (token 0 1 2 3),"-",(token 4 5),"-",(token 6 7); 0Nd]];
    fmt~"yyyy.mm.dd";
      [if[10 <> n; :0Nd];
       if[not (token[4]=".") and token[7]="."; :0Nd];
       if[not all (token 0 1 2 3 5 6 8 9) in "0123456789"; :0Nd];
       @["D"$; token; 0Nd]];
    fmt~"yyyy-mm-dd";
      [if[10 <> n; :0Nd];
       if[not (token[4]="-") and token[7]="-"; :0Nd];
       if[not all (token 0 1 2 3 5 6 8 9) in "0123456789"; :0Nd];
       @["D"$; token; 0Nd]];
    0Nd]
 }

/ Strip file extension: drop from the last "." onward.
/ "sales_transactions_2026-01-27.csv" -> "sales_transactions_2026-01-27"
.discovery.stripExt:{[fn]
  dots:where fn=".";
  $[0=count dots; fn; fn til last dots]
 }

/ Extract a date from a filename string by splitting on dateDelim and testing
/ each token with .discovery.parseToken. Returns first valid date or 0Nd.
.discovery.extractDateFromFilename:{[fmt; delim; fn]
  base:.discovery.stripExt fn;
  tokens:(string delim) vs base;
  dts:.discovery.parseToken[fmt;] each tokens;
  valid:dts where not null dts;
  $[0=count valid; 0Nd; first valid]
 }

/ ============================================================================
/ FOLDER-BASED DISCOVERY
/ ============================================================================

.discovery.scanFolder:{[src; ru; fmt; pattern; dir]
  entries:@[key; dir; {[e] `symbol$()}];
  if[0=count entries;
    :([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$())];
  result:([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$());
  {[result; src; ru; fmt; pattern; dir; entry]
    dt:.discovery.parseToken[fmt; string entry];
    if[null dt; :result];
    subdir:` sv dir,entry;
    files:@[key; subdir; {[e] `symbol$()}];
    matched:files where files like string pattern;
    if[0=count matched; :result];
    newRows:([]
      source:     (count matched)#enlist src;
      refreshUnit:(count matched)#enlist ru;
      date:       (count matched)#enlist dt;
      filepath:   {` sv (x;y)}[subdir;] each matched);
    result,newRows
  }[; src; ru; fmt; pattern; dir]/[result; entries]
 }

/ ============================================================================
/ FILENAME-BASED DISCOVERY
/ ============================================================================

.discovery.scanFilenames:{[src; ru; fmt; delim; pattern; dir]
  files:@[key; dir; {[e] `symbol$()}];
  matched:files where files like string pattern;
  if[0=count matched;
    :([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$())];
  result:([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$());
  {[result; src; ru; fmt; delim; dir; fn]
    dt:.discovery.extractDateFromFilename[fmt; delim; string fn];
    if[null dt; :result];
    fp:` sv dir,fn;
    result,([] source:enlist src; refreshUnit:enlist ru; date:enlist dt; filepath:enlist fp)
  }[; src; ru; fmt; delim; dir]/[result; matched]
 }

/ ============================================================================
/ ENTRY POINT
/ ============================================================================

/ Scan for all available work items across all sources in sourceConfig.
/ sourceConfig - table with cols: source, refreshUnit, filePattern,
/                dateFrom, dateFormat, dateDelim, delimiter, required, directory
/ Returns table: source, refreshUnit, date, filepath
.discovery.identifyWork:{[sourceConfig]
  result:([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$());
  n:count sourceConfig;
  if[0=n; :result];
  i:0;
  while[i<n;
    row:sourceConfig i;
    src:  row`source;
    ru:   row`refreshUnit;
    pat:  row`filePattern;
    frm:  row`dateFrom;
    fmt:  row`dateFormat;
    delim:row`dateDelim;
    dir:  hsym row`directory;
    newRows:$[frm=`folder;
        .discovery.scanFolder[src; ru; fmt; pat; dir];
        frm=`filename;
        .discovery.scanFilenames[src; ru; fmt; delim; pat; dir];
        ([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$())];
    result,:newRows;
    i+:1];
  result
 }

show "  discovery.q loaded"
