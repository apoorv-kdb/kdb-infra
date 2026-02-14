/ temporal_join.q
/ Point-in-time joins for time-varying reference data
/ Wraps kdb+'s aj (asof join) with common patterns for analytical workflows
/
/ Use case: reference data (e.g. fundability scores, credit ratings, business
/ hierarchies) changes over time. When joining to a fact table, you need the
/ value as of the fact's business date, not today's value.
/
/ Stateless: tables in, table out

\d .tj

/ ============================================================================
/ CORE JOINS
/ ============================================================================

/ Point-in-time join: attach reference data as of fact table's date
/ For each row in the fact table, finds the most recent reference row
/ where refDate <= factDate and keys match
/
/ Args:
/   fact: table - fact/transaction data with a date column
/   ref: table - reference data with an effective date and key columns
/   keyCols: symbol list - columns to match on (e.g. `business`asset_class)
/   factDateCol: symbol - date column in fact table (default `date)
/   refDateCol: symbol - effective date column in ref table (default `effective_date)
/   valueCols: symbol list - columns to bring from ref table, or (::) for all non-key/non-date
/ Returns: fact table with reference columns joined as of fact date
asOfJoin:{[fact; ref; keyCols; factDateCol; refDateCol; valueCols]
  if[(::) ~ factDateCol; factDateCol:`date];
  if[(::) ~ refDateCol; refDateCol:`effective_date];

  / Determine which columns to bring from reference
  if[(::) ~ valueCols;
    valueCols:(cols ref) except keyCols , enlist refDateCol];

  / Rename ref date column to match fact date column for aj
  ref:refDateCol xcol ref;
  renamedRefDateCol:factDateCol;

  / Ensure ref is sorted by key columns then date
  ref:`keyCols,enlist renamedRefDateCol xasc ref;

  / aj requires the time column last in the key list
  ajCols:keyCols , enlist factDateCol;

  / Perform asof join
  result:aj[ajCols; fact; (keyCols , enlist renamedRefDateCol , valueCols)#ref];

  result
 }

/ Simplified version when both tables use `date as the date column
/ and you want all non-key columns from the reference table
/ Args:
/   fact: table
/   ref: table with `date column for effective dates
/   keyCols: symbol list
/ Returns: fact table with reference columns joined
asOfJoinSimple:{[fact; ref; keyCols]
  valueCols:(cols ref) except keyCols , enlist `date;
  asOfJoin[fact; ref; keyCols; `date; `date; valueCols]
 }

/ ============================================================================
/ WINDOW JOINS
/ ============================================================================

/ Window join: attach aggregated reference data within a time window
/ For each fact row, finds reference rows within [factDate - windowDays, factDate]
/ and applies an aggregation function
/
/ Args:
/   fact: table
/   ref: table
/   keyCols: symbol list
/   factDateCol: symbol
/   refDateCol: symbol
/   windowDays: int - lookback window in days
/   aggSpecs: list of dicts with `col`fn`newCol
/     e.g. (`col`fn`newCol!(`score; avg; `avg_score); ...)
/ Returns: fact table with aggregated columns
windowJoin:{[fact; ref; keyCols; factDateCol; refDateCol; windowDays; aggSpecs]
  if[(::) ~ factDateCol; factDateCol:`date];
  if[(::) ~ refDateCol; refDateCol:`effective_date];

  / For each fact row, compute window boundaries
  fact:![fact; (); 0b; (enlist `__wstart)!(enlist (-; factDateCol; windowDays))];

  / Join and compute - row by row for correctness
  result:{[ref; keyCols; refDateCol; aggSpecs; row]
    / Filter ref to matching keys and date window
    refFiltered:ref;
    {[r; col; val] select from r where (col#r)[col] = val}[; ; ]/[refFiltered; keyCols; row keyCols];
    refFiltered:select from refFiltered
      where refFiltered[refDateCol] >= row`__wstart,
            refFiltered[refDateCol] <= row`date;

    / Apply aggregations
    {[row; refFiltered; spec]
      val:$[0 = count refFiltered; 0Nf; spec[`fn] refFiltered spec`col];
      row[spec`newCol]:val;
      row
    }[; refFiltered]/[row; aggSpecs]
  }[ref; keyCols; refDateCol; aggSpecs] each 0!fact;

  result:(0!flip result);
  ![result; (); 0b; enlist `__wstart]
 }

/ ============================================================================
/ REFERENCE DATA UTILITIES
/ ============================================================================

/ Get the current (latest) value from a reference table for each key
/ Args:
/   ref: table with date and key columns
/   keyCols: symbol list
/   dateCol: symbol (default `effective_date)
/ Returns: table with one row per unique key combination (latest values)
latest:{[ref; keyCols; dateCol]
  if[(::) ~ dateCol; dateCol:`effective_date];
  / Get last row per key group (assuming sorted by date)
  ref:`keyCols,enlist dateCol xasc ref;
  ?[ref; (); {x!x} keyCols;
    {x!((`last;) each x)} (cols ref) except keyCols]
 }

/ Get the value at a specific point in time for all keys
/ Args:
/   ref: table
/   keyCols: symbol list
/   dateCol: symbol (default `effective_date)
/   asOfDate: date
/ Returns: table with one row per key (values as of asOfDate)
snapshot:{[ref; keyCols; dateCol; asOfDate]
  if[(::) ~ dateCol; dateCol:`effective_date];
  / Filter to rows on or before asOfDate
  filtered:?[ref; enlist (<=; dateCol; asOfDate); 0b; ()];
  / Take latest per key
  latest[filtered; keyCols; dateCol]
 }

/ Build a history table showing all changes for a specific key
/ Args:
/   ref: table
/   keyCols: symbol list
/   keyVals: dict of col -> value (e.g. `business`asset_class!(`Trading; `Bond))
/   dateCol: symbol (default `effective_date)
/ Returns: table sorted by date showing all reference changes
history:{[ref; keyCols; keyVals; dateCol]
  if[(::) ~ dateCol; dateCol:`effective_date];
  filtered:ref;
  filtered:{[d; col; val] select from d where (col#d)[col] = val}/[filtered; key keyVals; value keyVals];
  dateCol xasc filtered
 }

\d .
