/ filters.q
/ Dynamic filtering for server query endpoints
/ Stateless: table in, table out

\d .filters

/ Apply inclusion filters
/ Args:
/   data: table
/   filters: dict of col -> value(s) to include
/ Returns: filtered table
apply:{[data; filters]
  if[(::) ~ filters; :data];
  {[data; col; vals]
    if[-11h = type vals; vals:enlist vals];
    select from data where (col#data)[col] in vals
  }/[data; key filters; value filters]
 }

/ Apply exclusion filters
/ Args:
/   data: table
/   exclusions: dict of col -> value(s) to exclude
/ Returns: filtered table
exclude:{[data; exclusions]
  if[(::) ~ exclusions; :data];
  {[data; col; vals]
    if[-11h = type vals; vals:enlist vals];
    select from data where not (col#data)[col] in vals
  }/[data; key exclusions; value exclusions]
 }

/ Apply both inclusions and exclusions
applyBoth:{[data; filters; exclusions]
  data:apply[data; filters];
  exclude[data; exclusions]
 }

/ Range filter for numeric columns
inRange:{[data; col; minVal; maxVal]
  select from data where (col#data)[col] >= minVal, (col#data)[col] <= maxVal
 }

/ Date range filter
dateRange:{[data; startDt; endDt]
  select from data where date within (startDt; endDt)
 }

/ Like filter for string/symbol columns
like:{[data; col; pattern]
  select from data where (string (col#data)[col]) like pattern
 }

\d .
