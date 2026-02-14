/ filters.q
/ Apply inclusion filters and exclusions to any table
/ Both filters and exclusions are column -> values dictionaries
/
/ Stateless: table in, table out

\d .filters

/ ============================================================================
/ CORE
/ ============================================================================

/ Apply inclusion filters
/ Keeps only rows where column values are in the specified set
/ Args:
/   data: table
/   filters: dict of col (symbol) -> values (list), or (::) for none
/ Returns: filtered table
apply:{[data; filters]
  if[(::) ~ filters; :data];
  if[99h <> type filters; :data];
  if[0 = count filters; :data];

  filterCols:(key filters) inter cols data;
  {[d; col; vals]
    vals:(),vals;
    ?[d; enlist (in; col; enlist vals); 0b; ()]
  }/[data; filterCols; filters filterCols]
 }

/ Apply exclusions
/ Removes rows where column values are in the specified set
/ Args:
/   data: table
/   exclusions: dict of col (symbol) -> values (list), or (::) for none
/ Returns: filtered table
exclude:{[data; exclusions]
  if[(::) ~ exclusions; :data];
  if[99h <> type exclusions; :data];
  if[0 = count exclusions; :data];

  exclCols:(key exclusions) inter cols data;
  {[d; col; vals]
    vals:(),vals;
    ?[d; enlist (not; (in; col; enlist vals)); 0b; ()]
  }/[data; exclCols; exclusions exclCols]
 }

/ Apply both filters and exclusions in one call
/ Filters applied first, then exclusions
/ Args:
/   data: table
/   filters: dict or (::)
/   exclusions: dict or (::)
/ Returns: filtered table
applyBoth:{[data; filters; exclusions]
  exclude[apply[data; filters]; exclusions]
 }

/ ============================================================================
/ COLUMN FILTERING
/ ============================================================================

/ Keep only specified columns
/ Args: data (table), keepCols (symbol list)
/ Returns: table with only those columns
selectCols:{[data; keepCols]
  validCols:keepCols inter cols data;
  validCols#data
 }

/ Drop specified columns
/ Args: data (table), dropCols (symbol list)
/ Returns: table without those columns
dropCols:{[data; dropCols]
  keepCols:(cols data) except dropCols;
  keepCols#data
 }

/ ============================================================================
/ DATE FILTERING
/ ============================================================================

/ Filter to a date range
/ Args: data (table), startDate (date), endDate (date)
/ Returns: table
dateRange:{[data; startDate; endDate]
  select from data where date within (startDate; endDate)
 }

/ Filter to last N days
/ Args: data (table), nDays (int)
/ Returns: table
lastNDays:{[data; nDays]
  cutoff:.z.d - nDays;
  select from data where date >= cutoff
 }

/ Filter to a specific month
/ Args: data (table), yr (int), mn (int)
/ Returns: table
month:{[data; yr; mn]
  select from data where (`month$date) = `month$"M"$string[yr],".",string mn
 }

/ ============================================================================
/ CONDITIONAL FILTERING
/ ============================================================================

/ Filter rows where a numeric column is within a range
/ Args: data (table), col (symbol), minVal (numeric), maxVal (numeric)
/ Returns: table
inRange:{[data; col; minVal; maxVal]
  ?[data; enlist (&; (>=; col; minVal); (<=; col; maxVal)); 0b; ()]
 }

/ Filter rows where a column is not null
/ Args: data (table), col (symbol)
/ Returns: table
notNull:{[data; col]
  ?[data; enlist (not; (null; col)); 0b; ()]
 }

/ Filter rows matching a like pattern on a symbol/string column
/ Args: data (table), col (symbol), pattern (string)
/ Returns: table
matching:{[data; col; pattern]
  ?[data; enlist (like; col; pattern); 0b; ()]
 }

\d .
