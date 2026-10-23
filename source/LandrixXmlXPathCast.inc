{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXPathEval: operations on atomic values (string value,
  effective boolean value, comparisons, arithmetic, casts). Included in
  the implementation section. }

function AtomicString(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  case Item.Kind of
    xikBoolean:
      if Item.BooleanValue then
        Result := 'true'
      else
        Result := 'false';
    xikInteger, xikDecimal:
      Result := LandrixXmlFormatDecimal(Item.Decimal);
    xikDouble:
      Result := LandrixXmlDoubleFormat(Item.DoubleValue);
  else
    Result := Item.Text;
  end;
end;

{ fn:boolean, the effective boolean value. }
function SequenceBoolean(const S: TLandrixXmlXPathSequence): Boolean;
begin
  Result := False;
  if S.Count = 0 then
    Exit;
  if S.Items[0].Kind = xikNode then
  begin
    Result := True;
    Exit;
  end;
  if S.Count > 1 then
    Fail('FORG0006', 'the effective boolean value of a sequence of several atomic values');
  case S.Items[0].Kind of
    xikBoolean:
      Result := S.Items[0].BooleanValue;
    xikString, xikUntypedAtomic, xikAnyUri:
      Result := S.Items[0].Text <> '';
    xikInteger, xikDecimal:
      Result := not LandrixXmlDecimalIsZero(S.Items[0].Decimal);
    xikDouble:
      Result := not LandrixXmlDoubleIsZero(S.Items[0].DoubleValue) and not LandrixXmlDoubleIsNaN(S.Items[0].DoubleValue);
  else
    Fail('FORG0006', 'no effective boolean value for ' + KindName(S.Items[0].Kind));
  end;
end;

function ToDouble(const Item: TLandrixXmlXPathItem): TLandrixXmlDouble;
begin
  if Item.Kind = xikDouble then
    Result := Item.DoubleValue
  else
    Result := LandrixXmlDoubleFromDecimal(Item.Decimal);
end;

function NumericEqualsInteger(const Item: TLandrixXmlXPathItem; Value: Integer): Boolean;
begin
  if Item.Kind = xikDouble then
    Result := LandrixXmlDoubleCompare(Item.DoubleValue, LandrixXmlDoubleFromInt64(Value)) = 0
  else
    Result := LandrixXmlDecimalCompare(Item.Decimal, LandrixXmlDecimalFromInt64(Value)) = 0;
end;

{ untypedAtomic or a string as xs:double, as Saxon parses it; XPath 2.0
  uses the lexical forms of XML Schema 1.0, which has no "+INF". }
function ParseDouble(const S: TLandrixXmlUtf8; Xp20: Boolean): TLandrixXmlDouble;
begin
  if not LandrixXmlDoubleTryParse(Trimmed(S), Result) or (Xp20 and (Trimmed(S) = '+INF')) then
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:double');
end;

function DateKindPrimitive(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXsdPrimitive;
begin
  case Kind of
    xikDate: Result := xspDate;
    xikDateTime: Result := xspDateTime;
  else
    Result := xspTime;
  end;
end;

function Pad(Value, Digits: Integer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(IntToStr(Value));
  while Length(Result) < Digits do
    Result := '0' + Result;
end;

{ The canonical lexical form XPath writes: fraction digits without
  trailing zeros, time zone Z for +00:00. }
function DateText(const D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind): TLandrixXmlUtf8;
var
  Seconds: TLandrixXmlUtf8;
  Tz: Integer;
begin
  Result := '';
  if Kind in [xikDate, xikDateTime] then
  begin
    if D.Year < 0 then
      Result := '-' + Pad(-D.Year, 4)
    else
      Result := Pad(D.Year, 4);
    Result := Result + '-' + Pad(D.Month, 2) + '-' + Pad(D.Day, 2);
  end;
  if Kind = xikDateTime then
    Result := Result + 'T';
  if Kind in [xikDateTime, xikTime] then
  begin
    Seconds := LandrixXmlFormatDecimal(D.Second);
    if (Length(Seconds) = 1) or ((Length(Seconds) > 1) and (Seconds[2] = '.')) then
      Seconds := '0' + Seconds;
    Result := Result + Pad(D.Hour, 2) + ':' + Pad(D.Minute, 2) + ':' + Seconds;
  end;
  if D.HasTimeZone then
  begin
    Tz := D.TimeZone;
    if Tz = 0 then
      Result := Result + 'Z'
    else
    begin
      if Tz < 0 then
      begin
        Result := Result + '-';
        Tz := -Tz;
      end
      else
        Result := Result + '+';
      Result := Result + Pad(Tz div 60, 2) + ':' + Pad(Tz mod 60, 2);
    end;
  end;
end;

{ 24:00:00 is 00:00:00 (of the next day for xs:dateTime). }
procedure NormalizeMidnight(var D: TLandrixXmlXsdDateTime; Kind: TLandrixXmlXPathItemKind);
var
  Days: Integer;
begin
  if D.Hour <> 24 then
    Exit;
  D.Hour := 0;
  if Kind <> xikDateTime then
    Exit;
  Inc(D.Day);
  case D.Month of
    4, 6, 9, 11: Days := 30;
    2:
      if (D.Year mod 4 = 0) and ((D.Year mod 100 <> 0) or (D.Year mod 400 = 0)) then
        Days := 29
      else
        Days := 28;
  else
    Days := 31;
  end;
  if D.Day > Days then
  begin
    D.Day := 1;
    Inc(D.Month);
    if D.Month > 12 then
    begin
      D.Month := 1;
      Inc(D.Year);
    end;
  end;
end;

function ParseDateKind(const S: TLandrixXmlUtf8; Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItem;
var
  T: TLandrixXmlXsdSimpleType;
  V: TLandrixXmlXsdValue;
  E: TLandrixXmlXsdError;
  Name: TLandrixXmlUtf8;
begin
  case Kind of
    xikDate: Name := 'date';
    xikDateTime: Name := 'dateTime';
  else
    Name := 'time';
  end;
  T := LandrixXmlXsdBuiltinType(Name);
  if not T.Validate(S, V, E) then
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:' +
      LandrixXmlUtf8ToString(Name));
  InitItem(Result, Kind);
  Result.DateTime := V.DateTime;
  NormalizeMidnight(Result.DateTime, Kind);
  Result.Text := DateText(Result.DateTime, Kind);
end;

function CompareDates(const A, B: TLandrixXmlXPathItem): Integer;
var
  VA, VB: TLandrixXmlXsdValue;
begin
  VA.MemberType := nil;
  VB.MemberType := nil;
  VA.Primitive := DateKindPrimitive(A.Kind);
  VB.Primitive := DateKindPrimitive(B.Kind);
  VA.DateTime := A.DateTime;
  VB.DateTime := B.DateTime;
  Result := LandrixXmlXsdCompareValues(VA, VB);
  if Result = LandrixXmlXsdIncomparable then
    Fail('FOER0000', 'comparing ' + KindName(A.Kind) + ' values with and without time zone is not supported');
end;

{ The result of a comparison from an ordering (-1, 0, 1; 2 = unordered). }
function Holds(Order: Integer; Op: TLandrixXmlXPathCompare): Boolean;
begin
  if Order = 2 then
  begin
    Result := Op = xpcNe;
    Exit;
  end;
  case Op of
    xpcEq: Result := Order = 0;
    xpcNe: Result := Order <> 0;
    xpcLt: Result := Order < 0;
    xpcLe: Result := Order <= 0;
    xpcGt: Result := Order > 0;
  else
    Result := Order >= 0;
  end;
end;

function CompareNumbers(const A, B: TLandrixXmlXPathItem): Integer;
begin
  if (A.Kind = xikDouble) or (B.Kind = xikDouble) then
  begin
    Result := LandrixXmlDoubleCompare(ToDouble(A), ToDouble(B));
    if Result = LandrixXmlDoubleUnordered then
      Result := 2;
  end
  else
    Result := LandrixXmlDecimalCompare(A.Decimal, B.Decimal);
end;

function CompareStrings(const A, B: TLandrixXmlUtf8): Integer;
begin
  { UTF-8 byte order is code point order }
  if A = B then
    Result := 0
  else if A < B then
    Result := -1
  else
    Result := 1;
end;

function CastTo(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathAtomicType;
  Xp20: Boolean): TLandrixXmlXPathItem; forward;
function DoubleToInteger(const D: TLandrixXmlDouble; Xp20: Boolean): TLandrixXmlDecimal; forward;

{ Compares two atomic values of comparable types (after the conversions of
  general or value comparisons). }
function CompareAtomic(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare): Boolean;
var
  Order: Integer;
begin
  if IsNumeric(A.Kind) and IsNumeric(B.Kind) then
    Order := CompareNumbers(A, B)
  else if IsStringLike(A.Kind) and IsStringLike(B.Kind) then
    Order := CompareStrings(A.Text, B.Text)
  else if (A.Kind = xikBoolean) and (B.Kind = xikBoolean) then
    Order := Ord(A.BooleanValue) - Ord(B.BooleanValue)
  else if (A.Kind in [xikDate, xikDateTime, xikTime]) and (A.Kind = B.Kind) then
    Order := CompareDates(A, B)
  else
  begin
    Fail('XPTY0004', 'cannot compare ' + KindName(A.Kind) + ' with ' + KindName(B.Kind));
    Order := 0;
  end;
  Result := Holds(Order, Op);
end;

{ "eq", "lt", ...: untypedAtomic is compared as a string. }
function ValueCompare(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare): Boolean;
begin
  Result := CompareAtomic(A, B, Op);
end;

{ The conversions of a general comparison for one pair. }
function ComparePair(const A, B: TLandrixXmlXPathItem; Op: TLandrixXmlXPathCompare; Xp20: Boolean): Boolean;
var
  X, Y: TLandrixXmlXPathItem;
begin
  X := A;
  Y := B;
  if X.Kind = xikUntypedAtomic then
  begin
    if IsNumeric(Y.Kind) then
      X := DoubleItem(ParseDouble(X.Text, Xp20))
    else if not IsStringLike(Y.Kind) then
      case Y.Kind of
        xikBoolean: X := CastTo(X, xatBoolean, Xp20);
        xikDate: X := CastTo(X, xatDate, Xp20);
        xikDateTime: X := CastTo(X, xatDateTime, Xp20);
        xikTime: X := CastTo(X, xatTime, Xp20);
      else
        { compared as they are: a type error }
      end;
  end;
  if Y.Kind = xikUntypedAtomic then
  begin
    if IsNumeric(X.Kind) then
      Y := DoubleItem(ParseDouble(Y.Text, Xp20))
    else if not IsStringLike(X.Kind) then
      case X.Kind of
        xikBoolean: Y := CastTo(Y, xatBoolean, Xp20);
        xikDate: Y := CastTo(Y, xatDate, Xp20);
        xikDateTime: Y := CastTo(Y, xatDateTime, Xp20);
        xikTime: Y := CastTo(Y, xatTime, Xp20);
      else
        { compared as they are: a type error }
      end;
  end;
  Result := CompareAtomic(X, Y, Op);
end;

function GeneralCompare(const A, B: TLandrixXmlXPathSequence; Op: TLandrixXmlXPathCompare;
  Xp20: Boolean): Boolean;
var
  I, J: Integer;
begin
  for I := 0 to A.Count - 1 do
    for J := 0 to B.Count - 1 do
      if ComparePair(A.Items[I], B.Items[J], Op, Xp20) then
      begin
        Result := True;
        Exit;
      end;
  Result := False;
end;

{ Arithmetic operands: untypedAtomic becomes xs:double. }
function NumericOperand(const Item: TLandrixXmlXPathItem; Xp20: Boolean): TLandrixXmlXPathItem;
begin
  if Item.Kind = xikUntypedAtomic then
    Result := DoubleItem(ParseDouble(Item.Text, Xp20))
  else if IsNumeric(Item.Kind) then
    Result := Item
  else
  begin
    if Item.Kind in [xikDate, xikDateTime, xikTime] then
      Fail('FOER0000', 'arithmetic on ' + KindName(Item.Kind) + ' is not supported');
    Fail('XPTY0004', 'arithmetic on ' + KindName(Item.Kind));
    Result := Item;
  end;
end;

function DecimalScaleOf(const Item: TLandrixXmlXPathItem): Integer;
begin
  if Item.Kind = xikInteger then
    Result := 0
  else
    Result := LandrixXmlDecimalScale(Item.Decimal);
end;

function Arithmetic(const A0, B0: TLandrixXmlXPathItem; Op: TLandrixXmlXPathArithmetic;
  Xp20: Boolean): TLandrixXmlXPathItem;
var
  A, B: TLandrixXmlXPathItem;
  DA, DB, Q: TLandrixXmlDouble;
  IsInt: Boolean;
begin
  A := NumericOperand(A0, Xp20);
  B := NumericOperand(B0, Xp20);
  if (A.Kind = xikDouble) or (B.Kind = xikDouble) then
  begin
    DA := ToDouble(A);
    DB := ToDouble(B);
    case Op of
      xpaAdd: Result := DoubleItem(LandrixXmlDoubleAdd(DA, DB));
      xpaSubtract: Result := DoubleItem(LandrixXmlDoubleSubtract(DA, DB));
      xpaMultiply: Result := DoubleItem(LandrixXmlDoubleMultiply(DA, DB));
      xpaDivide: Result := DoubleItem(LandrixXmlDoubleDivide(DA, DB));
      xpaModulo: Result := DoubleItem(LandrixXmlDoubleModulo(DA, DB));
    else
      begin
        if LandrixXmlDoubleIsZero(DB) then
          Fail('FOAR0001', 'integer division by zero');
        Q := LandrixXmlDoubleDivide(DA, DB);
        if LandrixXmlDoubleIsNaN(DA) or LandrixXmlDoubleIsNaN(DB) or LandrixXmlDoubleIsInfinite(DA) then
          Fail('FOAR0002', 'idiv of NaN or infinity');
        if LandrixXmlDoubleIsNaN(Q) or LandrixXmlDoubleIsInfinite(Q) then
          Fail('FOCA0002', 'the quotient of idiv is too large');
        Result := IntegerItem(DoubleToInteger(Q, Xp20));
      end;
    end;
    Exit;
  end;
  if (Op in [xpaDivide, xpaIntegerDivide, xpaModulo]) and LandrixXmlDecimalIsZero(B.Decimal) then
    Fail('FOAR0001', 'division by zero');
  if (A.Kind = xikInteger) and (B.Kind = xikInteger) then
  begin
    case Op of
      xpaAdd: Result := IntegerItem(LandrixXmlDecimalAdd(A.Decimal, B.Decimal));
      xpaSubtract: Result := IntegerItem(LandrixXmlDecimalSubtract(A.Decimal, B.Decimal));
      xpaMultiply: Result := IntegerItem(LandrixXmlDecimalMultiply(A.Decimal, B.Decimal));
      xpaDivide:
        begin
          Result := DecimalItem(LandrixXmlDecimalDivideIntegers(A.Decimal, B.Decimal, IsInt));
          if IsInt then
            Result.Kind := xikInteger;
        end;
      xpaIntegerDivide: Result := IntegerItem(LandrixXmlDecimalIntegerQuotient(A.Decimal, B.Decimal));
    else
      Result := IntegerItem(LandrixXmlDecimalModulo(A.Decimal, B.Decimal));
    end;
    Exit;
  end;
  case Op of
    xpaAdd: Result := DecimalItem(LandrixXmlDecimalAdd(A.Decimal, B.Decimal));
    xpaSubtract: Result := DecimalItem(LandrixXmlDecimalSubtract(A.Decimal, B.Decimal));
    xpaMultiply: Result := DecimalItem(LandrixXmlDecimalMultiply(A.Decimal, B.Decimal));
    xpaDivide:
      Result := DecimalItem(LandrixXmlDecimalDivideScaled(A.Decimal, B.Decimal, DecimalScaleOf(A), DecimalScaleOf(B)));
    xpaIntegerDivide: Result := IntegerItem(LandrixXmlDecimalIntegerQuotient(A.Decimal, B.Decimal));
  else
    Result := DecimalItem(LandrixXmlDecimalModulo(A.Decimal, B.Decimal));
  end;
end;

function UnaryOp(const Item: TLandrixXmlXPathItem; Negate, Xp20: Boolean): TLandrixXmlXPathItem;
begin
  Result := NumericOperand(Item, Xp20);
  if not Negate then
    Exit;
  if Result.Kind = xikDouble then
    Result.DoubleValue := LandrixXmlDoubleNegate(Result.DoubleValue)
  else
    Result.Decimal := LandrixXmlDecimalNegate(Result.Decimal);
end;

function RangeOf(const A, B: TLandrixXmlXPathSequence; Xp20: Boolean): TLandrixXmlXPathSequence;
var
  X, Y: TLandrixXmlXPathItem;
  Lo, Hi: Int64;
  I, Count: Integer;
begin
  Result := LandrixXmlXPathEmpty;
  if (A.Count = 0) or (B.Count = 0) then
    Exit;
  if (A.Count > 1) or (B.Count > 1) then
    Fail('XPTY0004', '"to" needs single items');
  X := A.Items[0];
  Y := B.Items[0];
  if X.Kind = xikUntypedAtomic then
    X := CastTo(X, xatInteger, Xp20);
  if Y.Kind = xikUntypedAtomic then
    Y := CastTo(Y, xatInteger, Xp20);
  if (X.Kind <> xikInteger) or (Y.Kind <> xikInteger) then
    Fail('XPTY0004', 'the operands of "to" must be integers');
  if LandrixXmlDecimalCompare(X.Decimal, Y.Decimal) > 0 then
    Exit;
  if LandrixXmlDecimalCompare(LandrixXmlDecimalSubtract(Y.Decimal, X.Decimal),
    LandrixXmlDecimalFromInt64(10000000)) >= 0 then
    Fail('FOAR0002', 'a range of more than 10000000 integers is not supported');
  if not LandrixXmlDecimalTryToInt64(X.Decimal, Lo) or not LandrixXmlDecimalTryToInt64(Y.Decimal, Hi) then
    Fail('FOAR0002', 'range bounds out of range');
  { at most 10000000 items, checked above }
  Count := Integer(Hi - Lo);
  for I := 0 to Count do
    LandrixXmlXPathAppend(Result, IntegerItemOf(Lo + I));
end;

{ Saxon converts a double below 2^63 with Java's (long) cast (the exact
  value truncated, 2^63 saturates to 2^63 - 1), larger ones through the
  shortest digits. }
function DoubleToIntegerAsSaxon(const D: TLandrixXmlDouble): TLandrixXmlDecimal;
var
  Limit, Exact: TLandrixXmlDecimal;
begin
  Limit := LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(High(Int64)), LandrixXmlDecimalFromInt64(1));
  Exact := LandrixXmlDoubleToDecimal(D);
  if LandrixXmlDecimalCompare(LandrixXmlDecimalAbs(Exact), Limit) <= 0 then
  begin
    Result := LandrixXmlDecimalRound(Exact, 0, xdrDown);
    if LandrixXmlDecimalCompare(Result, Limit) >= 0 then
      Result := LandrixXmlDecimalFromInt64(High(Int64));
  end
  else
    Result := LandrixXmlDoubleToInteger(D);
end;

{ A double as xs:integer: XPath 2.0 truncates the exact value. }
function DoubleToInteger(const D: TLandrixXmlDouble; Xp20: Boolean): TLandrixXmlDecimal;
begin
  if Xp20 then
    Result := LandrixXmlDecimalRound(LandrixXmlDoubleToDecimal(D), 0, xdrDown)
  else
    Result := DoubleToIntegerAsSaxon(D);
end;

{ An xs:anyURI as XML Schema 1.0 allows it: every "%" starts an escape of
  two hexadecimal digits, and a ":" before the first "/", "?" or "#" ends
  a scheme (a letter, then letters, digits, "+", "-" and "."). }
function AnyUriValid(const S: TLandrixXmlUtf8): Boolean;
var
  I, Colon: Integer;
begin
  Result := False;
  Colon := 0;
  for I := 1 to Length(S) do
    if S[I] in ['/', '?', '#'] then
      Break
    else if S[I] = ':' then
    begin
      Colon := I;
      Break;
    end;
  if Colon > 0 then
  begin
    if (Colon = 1) or not (S[1] in ['A'..'Z', 'a'..'z']) then
      Exit;
    for I := 2 to Colon - 1 do
      if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '+', '-', '.']) then
        Exit;
  end;
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '%' then
    begin
      if (I + 2 > Length(S)) or not (S[I + 1] in ['0'..'9', 'A'..'F', 'a'..'f']) or
        not (S[I + 2] in ['0'..'9', 'A'..'F', 'a'..'f']) then
        Exit;
      Inc(I, 2);
    end;
    Inc(I);
  end;
  Result := True;
end;

function BooleanFromText(const S: TLandrixXmlUtf8): TLandrixXmlXPathItem;
var
  T: TLandrixXmlUtf8;
begin
  T := Trimmed(S);
  if (T = 'true') or (T = '1') then
    Result := BooleanItem(True)
  else if (T = 'false') or (T = '0') then
    Result := BooleanItem(False)
  else
  begin
    Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(S, 60) + ''' to xs:boolean');
    Result := BooleanItem(False);
  end;
end;

function CastTo(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathAtomicType;
  Xp20: Boolean): TLandrixXmlXPathItem;
var
  D: TLandrixXmlDecimal;
  F: TLandrixXmlDouble;
  StringSource: Boolean;

  procedure NotAllowed;
  begin
    Fail('XPTY0004', 'cannot cast ' + KindName(Item.Kind) + ' to ' + LandrixXmlXPathAtomicTypeName(T));
  end;

begin
  { xs:anyURI casts only to strings (and anyURI) }
  StringSource := Item.Kind in [xikString, xikUntypedAtomic];
  InitItem(Result, xikString);
  case T of
    xatString:
      Result := StringItem(xikString, AtomicString(Item));
    xatUntypedAtomic, xatAnyAtomic:
      if T = xatAnyAtomic then
        Result := Item
      else
        Result := StringItem(xikUntypedAtomic, AtomicString(Item));
    xatAnyUri:
      if StringSource or (Item.Kind = xikAnyUri) then
      begin
        Result := StringItem(xikAnyUri, NormalizeSpace(Item.Text));
        { an xs:anyURI stays as it is (a cast to its own type) }
        if Xp20 and StringSource and not AnyUriValid(Result.Text) then
          Fail('FORG0001', 'invalid xs:anyURI ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + '''');
      end
      else
        NotAllowed;
    xatBoolean:
      case Item.Kind of
        xikBoolean:
          Result := Item;
        xikInteger, xikDecimal:
          Result := BooleanItem(not LandrixXmlDecimalIsZero(Item.Decimal));
        xikDouble:
          Result := BooleanItem(not LandrixXmlDoubleIsZero(Item.DoubleValue) and
            not LandrixXmlDoubleIsNaN(Item.DoubleValue));
      else
        if StringSource then
          Result := BooleanFromText(Item.Text)
        else
          NotAllowed;
      end;
    xatDecimal:
      case Item.Kind of
        xikInteger, xikDecimal:
          Result := DecimalItem(Item.Decimal);
        xikDouble:
          begin
            if LandrixXmlDoubleIsNaN(Item.DoubleValue) or LandrixXmlDoubleIsInfinite(Item.DoubleValue) then
              Fail('FOCA0002', 'cannot convert NaN or infinity to xs:decimal');
            Result := DecimalItem(LandrixXmlDoubleToDecimal(Item.DoubleValue));
          end;
        xikBoolean:
          Result := DecimalItem(LandrixXmlDecimalFromInt64(Ord(Item.BooleanValue)));
      else
        if StringSource then
        begin
          if not LandrixXmlTryParseDecimal(Item.Text, D) then
            Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + ''' to xs:decimal');
          Result := DecimalItem(D);
        end
        else
          NotAllowed;
      end;
    xatInteger:
      case Item.Kind of
        xikInteger:
          Result := Item;
        xikDecimal:
          Result := IntegerItem(LandrixXmlDecimalRound(Item.Decimal, 0, xdrDown));
        xikDouble:
          begin
            if LandrixXmlDoubleIsNaN(Item.DoubleValue) or LandrixXmlDoubleIsInfinite(Item.DoubleValue) then
              Fail('FOCA0002', 'cannot convert NaN or infinity to xs:integer');
            Result := IntegerItem(DoubleToInteger(Item.DoubleValue, Xp20));
          end;
        xikBoolean:
          Result := IntegerItemOf(Ord(Item.BooleanValue));
      else
        if StringSource then
        begin
          if not LandrixXmlTryParseDecimalInteger(Item.Text, D) then
            Fail('FORG0001', 'cannot convert ''' + LandrixXmlEscapeForMessage(Item.Text, 60) + ''' to xs:integer');
          Result := IntegerItem(D);
        end
        else
          NotAllowed;
      end;
    xatDouble:
      case Item.Kind of
        xikDouble:
          Result := Item;
        xikInteger, xikDecimal:
          Result := DoubleItem(LandrixXmlDoubleFromDecimal(Item.Decimal));
        xikBoolean:
          Result := DoubleItem(LandrixXmlDoubleFromInt64(Ord(Item.BooleanValue)));
      else
        if StringSource then
        begin
          F := ParseDouble(Item.Text, Xp20);
          Result := DoubleItem(F);
        end
        else
          NotAllowed;
      end;
    xatDate, xatDateTime, xatTime:
      begin
        if StringSource then
        begin
          case T of
            xatDate: Result := ParseDateKind(Item.Text, xikDate);
            xatDateTime: Result := ParseDateKind(Item.Text, xikDateTime);
          else
            Result := ParseDateKind(Item.Text, xikTime);
          end;
        end
        else if (Item.Kind = xikDate) and (T = xatDate) or (Item.Kind = xikDateTime) and (T = xatDateTime) or
          (Item.Kind = xikTime) and (T = xatTime) then
          Result := Item
        else if Item.Kind in [xikDate, xikDateTime, xikTime] then
          Fail('FOER0000', 'casts between ' + KindName(Item.Kind) + ' and ' + LandrixXmlXPathAtomicTypeName(T) +
            ' are not supported')
        else
          NotAllowed;
      end;
  else
    Fail('FOER0000', 'casts to ' + LandrixXmlXPathAtomicTypeName(T) + ' are not supported');
  end;
end;

function Castable(const Item: TLandrixXmlXPathItem; T: TLandrixXmlXPathAtomicType; Xp20: Boolean): Boolean;
begin
  try
    CastTo(Item, T, Xp20);
    Result := True;
  except
    on E: ELandrixXmlXPathError do
    begin
      if E.XPathCode = 'FOER0000' then
        raise;
      Result := False;
    end;
  end;
end;
