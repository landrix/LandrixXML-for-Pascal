{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXPathEval: xs:date, xs:dateTime and xs:time values in
  comparisons, arithmetic with durations and each other, casts between
  them, the time zone adjustments (F&O 2.0 10.4 to 10.8). Values without
  a time zone take the implicit time zone (Tz, minutes east of UTC) where
  F&O 2.0 needs one. Years follow XML Schema 1.0 as Xerces and the date
  parser count them: there is no year 0, -1 is the year before 1, and the
  leap year rule applies to the signed year, so the year -N is as long as
  the year N (-0004 is a leap year, -0001 is not). Included in
  LandrixXmlXPathCast.inc. }

{ The year as a continuous count of years (0 for -1, -1 for -2, ...),
  for month arithmetic. }
function YearCount(Year: Integer): Int64;
begin
  Result := Year;
  if Result < 0 then
    Inc(Result);
end;

function FloorDiv64(A, B: Int64): Int64;
begin
  Result := A div B;
  if (A mod B <> 0) and ((A < 0) <> (B < 0)) then
    Dec(Result);
end;

{ Days since 1970-01-01 of a date of the proleptic Gregorian calendar
  (Year positive). }
function PositiveDays(Year: Int64; Month, Day: Integer): Int64;
var
  Y, Era, Yoe, Doy, Doe, M: Int64;
begin
  Y := Year;
  if Month <= 2 then
    Dec(Y);
  Era := FloorDiv64(Y, 400);
  Yoe := Y - Era * 400;
  if Month > 2 then
    M := Int64(Month) - 3
  else
    M := Int64(Month) + 9;
  Doy := (153 * M + 2) div 5 + Int64(Day) - 1;
  Doe := Yoe * 365 + Yoe div 4 - Yoe div 100 + Doy;
  Result := Era * 146097 + Doe - 719468;
end;

{ The date of a day number of PositiveDays (any day number; the year may
  come out zero or negative, as an astronomical year). }
procedure PositiveCivil(Days: Int64; out Year: Int64; out Month, Day: Integer);
var
  Z, Era, Doe, Yoe, Doy, Mp: Int64;
begin
  Z := Days + 719468;
  Era := FloorDiv64(Z, 146097);
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe div 1460 + Doe div 36524 - Doe div 146096) div 365;
  Year := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe div 4 - Yoe div 100);
  Mp := (5 * Doy + 2) div 153;
  Day := Integer(Doy - (153 * Mp + 2) div 5 + 1);
  if Mp < 10 then
    Month := Integer(Mp + 3)
  else
    Month := Integer(Mp - 9);
  if Month <= 2 then
    Inc(Year);
end;

{ Days since 1970-01-01 of an XML Schema 1.0 date: positive years in the
  proleptic Gregorian calendar, the year -N with the days of the year N,
  the years before 1 following each other backwards from 0001-01-01. }
function DaysFromCivil(Year, Month, Day: Integer): Int64;
var
  N, First: Int64;
begin
  if Year > 0 then
    Result := PositiveDays(Year, Month, Day)
  else
  begin
    N := -Int64(Year);
    First := PositiveDays(1, 1, 1);
    Result := 2 * First - PositiveDays(N + 1, 1, 1) + PositiveDays(N, Month, Day) - PositiveDays(N, 1, 1);
  end;
end;

{ The date of a day number of DaysFromCivil; FODT0001 if the year does
  not fit. }
procedure CivilFromDays(Days: Int64; out Year, Month, Day: Integer);
var
  First, N, Doy, Y: Int64;
begin
  First := PositiveDays(1, 1, 1);
  if Days >= First then
    PositiveCivil(Days, Y, Month, Day)
  else
  begin
    { the year -N: N is the year of the mirrored day }
    PositiveCivil(2 * First - Days - 1, N, Month, Day);
    Doy := Days - (2 * First - PositiveDays(N + 1, 1, 1));
    PositiveCivil(PositiveDays(N, 1, 1) + Doy, Y, Month, Day);
    Y := -N;
  end;
  if (Y > High(Integer)) or (Y < -High(Integer)) then
    Fail('FODT0001', 'the year of the date is out of range');
  Year := Integer(Y);
end;

{ the leap year rule on the signed year, as the date parser applies it }
function DaysInMonth(Year, Month: Integer): Integer;
begin
  case Month of
    4, 6, 9, 11: Result := 30;
    2:
      if (Year mod 4 = 0) and ((Year mod 100 <> 0) or (Year mod 400 = 0)) then
        Result := 29
      else
        Result := 28;
  else
    Result := 31;
  end;
end;

{ The value as seconds since 1970-01-01T00:00:00 on its own clock (the
  time zone not applied): a date at 00:00:00, a time on 1972-12-31. }
function LocalSeconds(const D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind): TLandrixXmlDecimal;
var
  Days: Int64;
begin
  if Kind = xikTime then
    Days := DaysFromCivil(1972, 12, 31)
  else
    Days := DaysFromCivil(D.Year, D.Month, D.Day);
  if Kind = xikDate then
    Result := LandrixXmlDecimalFromInt64(Days * 86400)
  else
    Result := LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(Days * 86400 + Int64(D.Hour) * 3600 +
      Int64(D.Minute) * 60), D.Second);
end;

{ The value on the UTC time line: minus its time zone, or the implicit
  one Tz if it has none. }
function UtcSeconds(const D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind; Tz: Integer): TLandrixXmlDecimal;
var
  Zone: Integer;
begin
  if D.HasTimeZone then
    Zone := D.TimeZone
  else
    Zone := Tz;
  Result := LandrixXmlDecimalSubtract(LocalSeconds(D, Kind), LandrixXmlDecimalFromInt64(Int64(Zone) * 60));
end;

{ A value of Kind from seconds of LocalSeconds and a time zone (a time
  keeps the time of day only, a date the day only). }
function DateFromSeconds(const Seconds: TLandrixXmlDecimal; Kind: TLandrixXmlXPathItemKind;
  HasTimeZone: Boolean; TimeZone: Integer): TLandrixXmlXPathItem;
var
  D: TLandrixXmlXsdDateTime;
  WholeD: TLandrixXmlDecimal;
  Whole, Days, InDay: Int64;
begin
  WholeD := LandrixXmlDecimalRound(Seconds, 0, xdrFloor);
  if not LandrixXmlDecimalTryToInt64(WholeD, Whole) then
    Fail('FODT0001', 'the date is out of range');
  { no multiplication: Whole may be close to the Int64 limits }
  Days := Whole div 86400;
  InDay := Whole mod 86400;
  if InDay < 0 then
  begin
    Inc(InDay, 86400);
    Dec(Days);
  end;
  if Kind = xikTime then
  begin
    D.Year := 1972;
    D.Month := 12;
    D.Day := 31;
  end
  else
    CivilFromDays(Days, D.Year, D.Month, D.Day);
  if Kind = xikDate then
  begin
    D.Hour := 0;
    D.Minute := 0;
    D.Second := LandrixXmlDecimalZero;
  end
  else
  begin
    D.Hour := Integer(InDay div 3600);
    D.Minute := Integer(InDay mod 3600 div 60);
    D.Second := LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(InDay mod 60),
      LandrixXmlDecimalSubtract(Seconds, WholeD));
  end;
  D.HasTimeZone := HasTimeZone;
  if HasTimeZone then
    D.TimeZone := TimeZone
  else
    D.TimeZone := 0;
  Result := DateItem(Kind, D, DateText(D, Kind));
end;

{ The order of two values of the same kind (F&O 2.0 op:date-equal and
  the others: compared on the UTC time line). }
function CompareDates(const A, B: TLandrixXmlXPathItem; Tz: Integer): Integer;
begin
  Result := LandrixXmlDecimalCompare(UtcSeconds(ItemDateTime(A), A.Kind, Tz), UtcSeconds(ItemDateTime(B), B.Kind, Tz));
end;

{ date - date, dateTime - dateTime, time - time: an xs:dayTimeDuration }
function DateDifference(const A, B: TLandrixXmlXPathItem; Tz: Integer): TLandrixXmlXPathItem;
begin
  Result := DurationItem(xikDayTimeDuration, LandrixXmlDecimalZero,
    LandrixXmlDecimalSubtract(UtcSeconds(ItemDateTime(A), A.Kind, Tz), UtcSeconds(ItemDateTime(B), B.Kind, Tz)));
end;

{ A date, dateTime or time plus a duration (Negate: minus it): months
  move the year and month and keep the day if the month has it (else its
  last day), seconds move the instant on the value's own clock; a time
  wraps around midnight. }
function AddToDate(const Value, Duration: TLandrixXmlXPathItem; Negate: Boolean): TLandrixXmlXPathItem;
var
  D: TLandrixXmlXsdDateTime;
  Months, Total, Y: Int64;
  Seconds: TLandrixXmlDecimal;
begin
  D := ItemDateTime(Value);
  if Duration.Kind = xikYearMonthDuration then
  begin
    Months := ItemMonths(Duration);
    if Negate then
      Months := -Months;
    Total := YearCount(D.Year) * 12 + (Int64(D.Month) - 1) + Months;
    Y := FloorDiv64(Total, 12);
    D.Month := Integer(Total - Y * 12) + 1;
    if Y <= 0 then
      Dec(Y);
    if (Y > High(Integer)) or (Y < -High(Integer)) then
      Fail('FODT0001', 'the year of the date is out of range');
    D.Year := Integer(Y);
    if D.Day > DaysInMonth(D.Year, D.Month) then
      D.Day := DaysInMonth(D.Year, D.Month);
    Result := DateItem(Value.Kind, D, DateText(D, Value.Kind));
    Exit;
  end;
  Seconds := ItemSeconds(Duration);
  if Negate then
    Seconds := LandrixXmlDecimalNegate(Seconds);
  { a time only needs the seconds of a day (the duration may be huge) }
  if Value.Kind = xikTime then
    Seconds := LandrixXmlDecimalModulo(Seconds, LandrixXmlDecimalFromInt64(86400));
  Result := DateFromSeconds(LandrixXmlDecimalAdd(LocalSeconds(D, Value.Kind), Seconds), Value.Kind,
    D.HasTimeZone, D.TimeZone);
end;

{ The value with its time zone changed to the one given (HasZone False:
  removed): without a time zone it gets the new one on the same clock,
  with one it shows the same instant in the new one (F&O 2.0 10.7). }
function AdjustToTimeZone(const Value: TLandrixXmlXPathItem; HasZone: Boolean; Zone: Integer): TLandrixXmlXPathItem;
var
  D: TLandrixXmlXsdDateTime;
  Local: TLandrixXmlDecimal;
begin
  D := ItemDateTime(Value);
  if not D.HasTimeZone or not HasZone then
  begin
    D.HasTimeZone := HasZone;
    if HasZone then
      D.TimeZone := Zone
    else
      D.TimeZone := 0;
    Result := DateItem(Value.Kind, D, DateText(D, Value.Kind));
    Exit;
  end;
  Local := LandrixXmlDecimalAdd(LocalSeconds(D, Value.Kind), LandrixXmlDecimalFromInt64((Int64(Zone) - D.TimeZone) * 60));
  Result := DateFromSeconds(Local, Value.Kind, True, Zone);
end;

{ Casts between xs:date, xs:dateTime and xs:time (F&O 2.0 17.1.9): a
  dateTime gives its date or time, a date the dateTime at midnight; the
  time zone stays. A time has no date: XPTY0004. }
function CastDateKind(const Value: TLandrixXmlXPathItem; T: TLandrixXmlXPathItemKind): TLandrixXmlXPathItem;
var
  D: TLandrixXmlXsdDateTime;
begin
  D := ItemDateTime(Value);
  if (Value.Kind = xikTime) or (T = xikTime) and (Value.Kind = xikDate) then
    Fail('XPTY0004', 'cannot cast ' + KindName(Value.Kind) + ' to ' + LandrixXmlXPathAtomicTypeName(T));
  if T = xikDate then
  begin
    D.Hour := 0;
    D.Minute := 0;
    D.Second := LandrixXmlDecimalZero;
  end
  else if T = xikTime then
  begin
    D.Year := 1972;
    D.Month := 12;
    D.Day := 31;
  end;
  Result := DateItem(T, D, DateText(D, T));
end;

{ fn:dateTime: the date and the time of day; the time zone of either, or
  of both if it is the same (FORG0008 if they differ). }
function CombineDateTime(const DateValue, TimeValue: TLandrixXmlXPathItem): TLandrixXmlXPathItem;
var
  D, T: TLandrixXmlXsdDateTime;
begin
  D := ItemDateTime(DateValue);
  T := ItemDateTime(TimeValue);
  if D.HasTimeZone and T.HasTimeZone and (D.TimeZone <> T.TimeZone) then
    Fail('FORG0008', 'fn:dateTime: the date and the time have different time zones');
  D.Hour := T.Hour;
  D.Minute := T.Minute;
  D.Second := T.Second;
  if T.HasTimeZone then
  begin
    D.HasTimeZone := True;
    D.TimeZone := T.TimeZone;
  end;
  Result := DateItem(xikDateTime, D, DateText(D, xikDateTime));
end;

{ The arithmetic of F&O 2.0 10.6 on dates and times: Op is xpaAdd or
  xpaSubtract, the operands fit (DurationArithmetic checks). }
function DateArithmetic(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathArithmetic): TLandrixXmlXPathItem;
begin
  if A.Kind in DurationKinds then
    Result := AddToDate(B, A, False)
  else
    Result := AddToDate(A, B, Op = xpaSubtract);
end;
