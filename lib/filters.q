/ filters.q
/ Dynamic filtering for server query endpoints
/ Stateless: table in, table out

/ Apply inclusion filters
/ Args:
/   data: table
/   filters: dict of col -> value(s) to include
/ Returns: filtered table
.filters.apply:{[data; filters]
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
.filters.exclude:{[data; exclusions]
  if[(::) ~ exclusions; :data];
  {[data; col; vals]
    if[-11h = type vals; vals:enlist vals];
    select from data where not (col#data)[col] in vals
  }/[data; key exclusions; value exclusions]
 }

/ Apply both inclusions and exclusions
.filters.applyBoth:{[data; filters; exclusions]
  data:.filters.apply[data; filters];
  .filters.exclude[data; exclusions]
 }

/ Range filter for numeric columns
.filters.inRange:{[data; col; minVal; maxVal]
  select from data where (col#data)[col] >= minVal, (col#data)[col] <= maxVal
 }

/ Date range filter
.filters.dateRange:{[data; startDt; endDt]
  select from data where date within (startDt; endDt)
 }

/ Like filter for string/symbol columns
.filters.like:{[data; col; pattern]
  select from data where (string (col#data)[col]) like pattern
 }
