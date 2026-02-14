/ dates.q
/ Date utilities for analytical queries
/ AsOf date resolution, previous date, business day awareness, date ranges
/
/ Stateless: operates on date lists or tables

\d .dates

/ ============================================================================
/ ASOF RESOLUTION
/ ============================================================================

/ Find max date <= target from a list of available dates
/ Args: dates (date list, sorted asc), target (date)
/ Returns: date or 0Nd
asOf:{[dates; target]
  valid:dates where dates <= target;
  $[0 = count valid; 0Nd; last valid]
 }

/ Find the date before a given date from a list
/ Args: dates (date list, sorted asc), dt (date)
/ Returns: date or 0Nd
prev:{[dates; dt]
  if[null dt; :0Nd];
  valid:dates where dates < dt;
  $[0 = count valid; 0Nd; last valid]
 }

/ Find the date after a given date from a list
/ Args: dates (date list, sorted asc), dt (date)
/ Returns: date or 0Nd
next:{[dates; dt]
  if[null dt; :0Nd];
  valid:dates where dates > dt;
  $[0 = count valid; 0Nd; first valid]
 }

/ Resolve both asOf and previous in one call
/ Args: dates (date list, sorted asc), target (date)
/ Returns: dict `current`previous
asOfPair:{[dates; target]
  c:asOf[dates; target];
  p:prev[dates; c];
  `current`previous!(c; p)
 }

/ ============================================================================
/ AVAILABLE DATES FROM TABLE
/ ============================================================================

/ Extract sorted distinct dates from a table
/ Args: data (table with date column)
/ Returns: sorted date list
fromTable:{[data]
  asc distinct exec date from data
 }

/ ============================================================================
/ BUSINESS DAYS
/ ============================================================================

/ Default holidays (empty - override with setHolidays)
holidays:`date$()

/ Set holiday calendar
/ Args: hols (date list)
setHolidays:{[hols]
  `.dates.holidays set asc distinct hols;
 }

/ Load holidays from a CSV file
/ Expects a single column of dates
loadHolidays:{[filepath]
  hols:@[{"D"$read0 x}; hsym `$string filepath; {[e] `date$()}];
  setHolidays[hols];
 }

/ Check if a date is a business day (not weekend, not holiday)
/ Args: dt (date)
/ Returns: boolean
isBizDay:{[dt]
  dow:dt mod 7;
  / Saturday = 6, Sunday = 0 in q's mod 7
  isWeekend:dow in 0 6;
  isHoliday:dt in holidays;
  not isWeekend | isHoliday
 }

/ Get the next business day on or after a date
/ Args: dt (date)
/ Returns: date
nextBizDay:{[dt]
  $[isBizDay dt; dt; nextBizDay dt + 1]
 }

/ Get the previous business day on or before a date
/ Args: dt (date)
/ Returns: date
prevBizDay:{[dt]
  $[isBizDay dt; dt; prevBizDay dt - 1]
 }

/ Get the next business day strictly after a date
/ Args: dt (date)
/ Returns: date
nextBizDayAfter:{[dt]
  nextBizDay[dt + 1]
 }

/ Get the previous business day strictly before a date
/ Args: dt (date)
/ Returns: date
prevBizDayBefore:{[dt]
  prevBizDay[dt - 1]
 }

/ Get N business days back from a date
/ Args: dt (date), n (int)
/ Returns: date
nBizDaysBack:{[dt; n]
  {[x] .dates.prevBizDayBefore x}/[n; dt]
 }

/ Get N business days forward from a date
/ Args: dt (date), n (int)
/ Returns: date
nBizDaysForward:{[dt; n]
  {[x] .dates.nextBizDayAfter x}/[n; dt]
 }

/ Count business days between two dates (exclusive of end)
/ Args: startDate (date), endDate (date)
/ Returns: long
bizDaysBetween:{[startDate; endDate]
  allDays:startDate + til (endDate - startDate);
  sum isBizDay each allDays
 }

/ Generate list of business days in a range (inclusive)
/ Args: startDate (date), endDate (date)
/ Returns: date list
bizDayRange:{[startDate; endDate]
  allDays:startDate + til 1 + endDate - startDate;
  allDays where isBizDay each allDays
 }

/ ============================================================================
/ DATE RANGE GENERATION
/ ============================================================================

/ Generate month-end dates for a range
/ Args: startDate (date), endDate (date)
/ Returns: date list of month ends
monthEnds:{[startDate; endDate]
  months:startDate + til 1 + endDate - startDate;
  months:distinct `month$months;
  / Last day of each month: first of next month minus 1
  {("d"$"m"$x + 1) - 1} each months
 }

/ Generate month-start dates for a range
/ Args: startDate (date), endDate (date)
/ Returns: date list of month starts
monthStarts:{[startDate; endDate]
  allDays:startDate + til 1 + endDate - startDate;
  distinct "d"$`month$allDays
 }

/ Generate quarter-end dates for a range
/ Args: startDate (date), endDate (date)
/ Returns: date list
quarterEnds:{[startDate; endDate]
  me:monthEnds[startDate; endDate];
  me where (`mm$me) in 3 6 9 12
 }

/ Get the end of month for a given date
/ Args: dt (date)
/ Returns: date
eom:{[dt]
  ("d"$1 + `month$dt) - 1
 }

/ Get the start of month for a given date
/ Args: dt (date)
/ Returns: date
som:{[dt]
  "d"$`month$dt
 }

\d .
