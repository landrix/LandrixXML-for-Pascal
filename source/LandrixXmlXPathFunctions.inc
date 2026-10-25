{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXPathEval: the built-in functions, with the argument
  rules of XPath 2.0, or of XPath 3.1 as Saxon 12 applies them in the
  Saxon profile (string-join takes any atomic values), and the conversion
  of user function arguments.
  Included at the end of the implementation section. }

function TLandrixXmlXPathEvaluator.ConvertTo(const S: TLandrixXmlXPathSequence;
  const T: TLandrixXmlXPathSequenceType; const FunctionName: string; AsXPath20: Boolean): TLandrixXmlXPathSequence;
var
  I: Integer;
  Item: TLandrixXmlXPathItem;
  A: TLandrixXmlXPathSequence;
  Ok: Boolean;
begin
  { no "as": no conversion, any number of items }
  if not T.Declared then
  begin
    Result := S;
    Exit;
  end;
  if T.Kind = xtkAnyItem then
    Result := S
  else if T.Kind = xtkEmpty then
  begin
    if S.Count > 0 then
      Fail('XPTY0004', FunctionName + ': an empty sequence was expected, got ' + IntToStr(S.Count) + ' items');
    Result := S;
  end
  else if T.Kind = xtkNode then
  begin
    for I := 0 to S.Count - 1 do
      if S.Items[I].Kind <> xikNode then
        Fail('XPTY0004', FunctionName + ': a node was expected')
      else if not NodeMatches(S.Items[I].Node, T) then
        Fail('XPTY0004', FunctionName + ': the node does not match ' + LandrixXmlXPathSequenceTypeName(T));
    Result := S;
  end
  else
  begin
    A := Atomize(S);
    Result := LandrixXmlXPathEmpty;
    for I := 0 to A.Count - 1 do
    begin
      Item := A.Items[I];
      if (Item.Kind = xikUntypedAtomic) and (T.AtomicType <> xikAnyAtomic) and (T.AtomicType <> xikUntypedAtomic) then
        Item := CastTo(Item, T.AtomicType, AsXPath20)
      else
      begin
        { promotions: integer and decimal to float and double, float to
          double, anyURI to string }
        Ok := True;
        case T.AtomicType of
          xikAnyAtomic: ;
          xikString:
            if Item.Kind = xikAnyUri then
              Item := StringItem(xikString, Item.Text)
            else
              Ok := AtomicKindMatches(Item.Kind, xikString);
          xikUntypedAtomic: Ok := Item.Kind = xikUntypedAtomic;
          xikBoolean: Ok := Item.Kind = xikBoolean;
          xikDecimal: Ok := AtomicKindMatches(Item.Kind, xikDecimal);
          xikInteger: Ok := AtomicKindMatches(Item.Kind, xikInteger);
          xikDouble:
            if BasicKind(Item.Kind) in [xikInteger, xikDecimal, xikFloat] then
              Item := DoubleItem(ToDouble(Item))
            else
              Ok := Item.Kind = xikDouble;
          xikFloat:
            if BasicKind(Item.Kind) in [xikInteger, xikDecimal] then
              Item := FloatItem(DecimalToFloat(ItemDecimal(Item), AsXPath20))
            else
              Ok := Item.Kind = xikFloat;
          xikDate: Ok := Item.Kind = xikDate;
          xikDateTime: Ok := Item.Kind = xikDateTime;
          xikTime: Ok := Item.Kind = xikTime;
          xikAnyUri: Ok := Item.Kind = xikAnyUri;
          xikNonPositiveInteger .. xikPositiveInteger, xikNormalizedString .. xikENTITY,
          xikDuration, xikYearMonthDuration, xikDayTimeDuration, xikGYearMonth .. xikGMonth, xikHexBinary,
          xikBase64Binary:
            Ok := AtomicKindMatches(Item.Kind, T.AtomicType);
        else
          Ok := False;
        end;
        if not Ok then
          Fail('XPTY0004', FunctionName + ': ' + KindName(Item.Kind) + ' does not match ' +
            LandrixXmlXPathAtomicTypeName(T.AtomicType));
      end;
      LandrixXmlXPathAppend(Result, Item);
    end;
  end;
  case T.Occurrence of
    xocOne:
      if Result.Count <> 1 then
        Fail('XPTY0004', FunctionName + ': exactly one item was expected, got ' + IntToStr(Result.Count));
    xocOptional:
      if Result.Count > 1 then
        Fail('XPTY0004', FunctionName + ': at most one item was expected, got ' + IntToStr(Result.Count));
    xocOneOrMore:
      if Result.Count = 0 then
        Fail('XPTY0004', FunctionName + ': at least one item was expected');
  else
    { any number }
  end;
end;

{ years-from-duration() ... seconds-from-duration(): the component of
  the canonical form, with the duration's sign }
function DurationComponent(const D: TLandrixXmlXPathItem; Id: TLandrixXmlXPathFunctionId): TLandrixXmlXPathItem;
var
  M, Whole, V: Int64;
  Abs: TLandrixXmlDecimal;
  Negative: Boolean;
begin
  M := ItemMonths(D);
  Negative := (M < 0) or (LandrixXmlDecimalSign(ItemSeconds(D)) < 0);
  if M < 0 then
    M := -M;
  Abs := LandrixXmlDecimalAbs(ItemSeconds(D));
  if not LandrixXmlDecimalTryToInt64(LandrixXmlDecimalRound(Abs, 0, xdrDown), Whole) then
    Whole := 0;
  if Id = xfnSecondsFromDuration then
  begin
    Abs := LandrixXmlDecimalSubtract(Abs, LandrixXmlDecimalFromInt64(Whole - Whole mod 60));
    if Negative then
      Abs := LandrixXmlDecimalNegate(Abs);
    Result := DecimalItem(Abs);
    Exit;
  end;
  case Id of
    xfnYearsFromDuration: V := M div 12;
    xfnMonthsFromDuration: V := M mod 12;
    xfnDaysFromDuration: V := Whole div 86400;
    xfnHoursFromDuration: V := Whole mod 86400 div 3600;
  else
    V := Whole mod 3600 div 60;
  end;
  if Negative then
    V := -V;
  Result := IntegerItemOf(V);
end;

{ year-from-dateTime() ... seconds-from-time(): a component of the value
  as it is written (no time zone applied). Saxon rounds the seconds to
  microseconds (ties up). }
function DateComponent(const V: TLandrixXmlXPathItem; Id: TLandrixXmlXPathFunctionId; Xp20: Boolean): TLandrixXmlXPathItem;
var
  D: TLandrixXmlXsdDateTime;
begin
  D := ItemDateTime(V);
  case Id of
    xfnYearFromDateTime, xfnYearFromDate: Result := IntegerItemOf(D.Year);
    xfnMonthFromDateTime, xfnMonthFromDate: Result := IntegerItemOf(D.Month);
    xfnDayFromDateTime, xfnDayFromDate: Result := IntegerItemOf(D.Day);
    xfnHoursFromDateTime, xfnHoursFromTime: Result := IntegerItemOf(D.Hour);
    xfnMinutesFromDateTime, xfnMinutesFromTime: Result := IntegerItemOf(D.Minute);
  else
    if Xp20 then
      Result := DecimalItem(D.Second)
    else
      Result := DecimalItem(LandrixXmlDecimalRound(D.Second, 6, xdrHalfCeiling));
  end;
end;

{ A double argument rounded as fn:round does, for positions. }
function RoundedDouble(const D: TLandrixXmlDouble): TLandrixXmlDouble;
begin
  Result := LandrixXmlDoubleRound(D, 0, xdrHalfCeiling);
end;

{ True if position P (an integer) is >= Start and < Stop (doubles; NaN never). }
function InRange(P: Integer; const Start, Stop: TLandrixXmlDouble; HasStop: Boolean): Boolean;
var
  DP: TLandrixXmlDouble;
  C: Integer;
begin
  DP := LandrixXmlDoubleFromInt64(P);
  C := LandrixXmlDoubleCompare(DP, Start);
  Result := (C <> LandrixXmlDoubleUnordered) and (C >= 0);
  if Result and HasStop then
  begin
    C := LandrixXmlDoubleCompare(DP, Stop);
    Result := (C <> LandrixXmlDoubleUnordered) and (C < 0);
  end;
end;

function TLandrixXmlXPathEvaluator.CallFunction(Index: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  Id: TLandrixXmlXPathFunctionId;
  ArgCount, I, J, K, Len: Integer;
  A, B: TLandrixXmlXPathSequence;
  S, T, R: TLandrixXmlUtf8;
  Item, Acc: TLandrixXmlXPathItem;
  CPs, Map, Trans: TLandrixXmlCodePoints;
  Parts: TLandrixXmlUtf8Array;
  Start, Stop: TLandrixXmlDouble;
  V64: Int64;
  Def: TLandrixXmlXPathFunctionDef;
  Args: array of TLandrixXmlXPathSequence;
  Re: TLandrixXmlRegex;
  Found, HasDouble, HasFloat: Boolean;
  NaNAt: Integer;
  Name: string;
  T2: TLandrixXmlXPathItemKind;
  OwnTree: TLandrixXmlXPathTree;

  function Arg(K: Integer): TLandrixXmlXPathSequence;
  begin
    Result := Eval(FNodes[Index].Children[K], Context, Position, Size, ContextItem);
  end;

  function ContextSeq: TLandrixXmlXPathSequence;
  begin
    if ContextItem.Count > 0 then
      Result := ContextItem
    else if Context >= 0 then
      Result := LandrixXmlXPathNodeItem(Context)
    else
    begin
      Fail('XPDY0002', Name + ': the context item is absent');
      Result := LandrixXmlXPathEmpty;
    end;
  end;

  { an optional single atomic argument }
  function OptAtom(K: Integer; out Value: TLandrixXmlXPathItem): Boolean;
  var
    V: TLandrixXmlXPathSequence;
  begin
    V := Atomize(Arg(K));
    if V.Count > 1 then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' has more than one item');
    Result := V.Count = 1;
    if Result then
      Value := V.Items[0];
  end;

  { an xs:string? argument: '' for the empty sequence }
  function StrArg(K: Integer): TLandrixXmlUtf8;
  var
    V: TLandrixXmlXPathItem;
  begin
    Result := '';
    if not OptAtom(K, V) then
      Exit;
    if not IsStringLike(V.Kind) then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' is ' + KindName(V.Kind) + ', not xs:string');
    Result := V.Text;
  end;

  { an xs:string argument that must not be empty }
  function ReqStrArg(K: Integer): TLandrixXmlUtf8;
  var
    V: TLandrixXmlXPathItem;
  begin
    if not OptAtom(K, V) then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' must not be empty');
    if not IsStringLike(V.Kind) then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' is ' + KindName(V.Kind) + ', not xs:string');
    Result := V.Text;
  end;

  { an xs:double argument (untypedAtomic and other numbers converted) }
  function DoubleArg(K: Integer): TLandrixXmlDouble;
  var
    V: TLandrixXmlXPathItem;
  begin
    if not OptAtom(K, V) then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' is empty');
    V := NumericOperand(V, Xp20);
    Result := ToDouble(V);
  end;

  function IntArg(K: Integer): Integer;
  var
    V: TLandrixXmlXPathItem;
    I64: Int64;
  begin
    if not OptAtom(K, V) then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' is empty');
    if V.Kind = xikUntypedAtomic then
      V := CastTo(V, xikInteger, Xp20);
    if BasicKind(V.Kind) <> xikInteger then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' must be an integer');
    if not LandrixXmlDecimalTryToInt64(ItemDecimal(V), I64) or (I64 > High(Integer)) or (I64 < Low(Integer)) then
      Fail('FOAR0002', Name + ': integer out of range');
    Result := Integer(I64);
  end;

  { the node argument of name(), local-name(), ...: -1 for the empty sequence }
  function NodeArg: Integer;
  var
    V: TLandrixXmlXPathSequence;
  begin
    if ArgCount = 0 then
      V := ContextSeq
    else
      V := Arg(0);
    Result := -1;
    if V.Count = 0 then
      Exit;
    if (V.Count > 1) or (V.Items[0].Kind <> xikNode) then
      Fail('XPTY0004', Name + ': a single node was expected');
    Result := V.Items[0].Node;
  end;

  function Compile(PatternArg, FlagArg: Integer): TLandrixXmlRegex;
  var
    Flags: TLandrixXmlUtf8;
  begin
    Flags := '';
    if (FlagArg >= 0) and (FlagArg < ArgCount) then
      Flags := ReqStrArg(FlagArg);
    Result := Regex(ReqStrArg(PatternArg), Flags);
  end;

  function NumericKind(const V: TLandrixXmlXPathItem): TLandrixXmlXPathItem;
  begin
    if not IsNumeric(V.Kind) and (V.Kind <> xikUntypedAtomic) then
      Fail('XPTY0004', Name + ': ' + KindName(V.Kind) + ' is not a number');
    Result := NumericOperand(V, Xp20);
  end;

  { equality as fn:distinct-values and fn:index-of see it }
  function SameValue(const X, Y: TLandrixXmlXPathItem; NaNEqual: Boolean): Boolean;
  var
    P, Q: TLandrixXmlXPathItem;
  begin
    P := X;
    Q := Y;
    if P.Kind = xikUntypedAtomic then
      P.Kind := xikString;
    if Q.Kind = xikUntypedAtomic then
      Q.Kind := xikString;
    if IsNumeric(P.Kind) and IsNumeric(Q.Kind) then
    begin
      if (P.Kind in [xikDouble, xikFloat]) and (Q.Kind in [xikDouble, xikFloat]) and
        LandrixXmlDoubleIsNaN(ItemDouble(P)) and LandrixXmlDoubleIsNaN(ItemDouble(Q)) then
      begin
        Result := NaNEqual;
        Exit;
      end;
      Result := CompareNumbers(P, Q, Xp20) = 0;
    end
    else if IsStringLike(P.Kind) and IsStringLike(Q.Kind) then
      Result := P.Text = Q.Text
    else if (P.Kind = xikBoolean) and (Q.Kind = xikBoolean) then
      Result := ItemBoolean(P) = ItemBoolean(Q)
    else if (P.Kind in [xikDate, xikDateTime, xikTime]) and (P.Kind = Q.Kind) then
      Result := CompareDates(P, Q, FImplicitTimeZone) = 0
    else if (P.Kind in DurationKinds) and (Q.Kind in DurationKinds) then
      Result := CompareDurations(P, Q, xpcEq) = 0
    else if (P.Kind in GregorianKinds) and (P.Kind = Q.Kind) then
      Result := CompareGregorian(P, Q, xpcEq, FImplicitTimeZone) = 0
    else if (P.Kind in BinaryKinds) and (P.Kind = Q.Kind) then
      Result := P.Text = Q.Text
    else
      Result := False;
  end;

begin
  CPs := nil;
  Map := nil;
  Trans := nil;
  Parts := nil;
  K := 0;
  N := @FNodes[Index];
  ArgCount := Integer(Length(N^.Children));
  if N^.Op < 0 then
  begin
    { a user function }
    if (FFunctions = nil) or (-1 - N^.Op >= FFunctions.Count) then
      Fail('XPST0017', 'user function ' + IntToStr(-1 - N^.Op) + ' is not defined');
    Def := TLandrixXmlXPathFunctionDef(FFunctions[-1 - N^.Op]);
    Args := nil;
    SetLength(Args, ArgCount);
    for I := 0 to ArgCount - 1 do
      Args[I] := Arg(I);
    Result := CallUser(Def, Args);
    Exit;
  end;
  Id := TLandrixXmlXPathFunctionId(N^.Op);
  Name := LandrixXmlXPathFunctionName(Id) + '()';
  Result := LandrixXmlXPathEmpty;
  case Id of
    xfnNot:
      Result := BooleanSeq(not SequenceBoolean(Arg(0)));
    xfnTrue:
      Result := BooleanSeq(True);
    xfnFalse:
      Result := BooleanSeq(False);
    xfnBoolean:
      Result := BooleanSeq(SequenceBoolean(Arg(0)));
    xfnCount:
      Result := SingleSeq(IntegerItemOf(Arg(0).Count));
    xfnExists:
      Result := BooleanSeq(Arg(0).Count > 0);
    xfnEmpty:
      Result := BooleanSeq(Arg(0).Count = 0);
    xfnSum, xfnAvg:
      begin
        A := Atomize(Arg(0));
        if A.Count = 0 then
        begin
          if Id = xfnAvg then
            Exit;
          if ArgCount > 1 then
          begin
            Result := Atomize(Arg(1));
            if Result.Count > 1 then
              Fail('XPTY0004', Name + ': the zero value must be a single item');
          end
          else
            Result := SingleSeq(IntegerItemOf(0));
          Exit;
        end;
        { numbers, or durations of one subtype }
        if A.Items[0].Kind in [xikYearMonthDuration, xikDayTimeDuration] then
        begin
          Acc := A.Items[0];
          for I := 1 to A.Count - 1 do
          begin
            { Saxon reports the missing addition of two durations }
            if (A.Items[I].Kind <> Acc.Kind) and (A.Items[I].Kind in DurationKinds) and not Xp20 and
              (Id = xfnSum) then
              Fail('XPTY0004', Name + ': ' + KindName(A.Items[I].Kind) + ' and ' + KindName(Acc.Kind) +
                ' cannot be added')
            else if A.Items[I].Kind <> Acc.Kind then
              Fail('FORG0006', Name + ': ' + KindName(A.Items[I].Kind) + ' and ' + KindName(Acc.Kind) +
                ' cannot be added');
            Acc := Arithmetic(Acc, A.Items[I], xpaAdd, Xp20, FImplicitTimeZone);
          end;
        end
        else
        begin
          if not IsNumeric(A.Items[0].Kind) and (A.Items[0].Kind <> xikUntypedAtomic) then
            Fail('FORG0006', Name + ': ' + KindName(A.Items[0].Kind) + ' is not a number');
          Acc := NumericOperand(A.Items[0], Xp20);
          for I := 1 to A.Count - 1 do
          begin
            Item := A.Items[I];
            if not IsNumeric(Item.Kind) and (Item.Kind <> xikUntypedAtomic) then
              Fail('FORG0006', Name + ': ' + KindName(Item.Kind) + ' is not a number');
            Acc := Arithmetic(Acc, Item, xpaAdd, Xp20, FImplicitTimeZone);
          end;
        end;
        { a single number is the sum as it is (no addition, so no promotion
          to the type xs:integer for its derived types) }
        if (Id = xfnSum) and (A.Count = 1) and IsNumeric(A.Items[0].Kind) then
          Acc := A.Items[0];
        { the average of durations is the exact quotient (Saxon too) }
        if (Id = xfnAvg) and (Acc.Kind in DurationKinds) then
          Acc := ScaleDuration(Acc, IntegerItemOf(A.Count), True, True)
        else if Id = xfnAvg then
          Acc := Arithmetic(Acc, IntegerItemOf(A.Count), xpaDivide, Xp20, FImplicitTimeZone);
        Result := SingleSeq(Acc);
      end;
    xfnMin, xfnMax:
      begin
        A := Atomize(Arg(0));
        if A.Count = 0 then
          Exit;
        { a copy: A may be the storage of a variable }
        A.Items := Copy(A.Items, 0, A.Count);
        HasDouble := False;
        HasFloat := False;
        NaNAt := -1;
        for I := 0 to A.Count - 1 do
        begin
          if A.Items[I].Kind = xikUntypedAtomic then
            A.Items[I] := DoubleItem(ParseDouble(A.Items[I].Text, Xp20));
          if A.Items[I].Kind in [xikDouble, xikFloat] then
          begin
            if A.Items[I].Kind = xikDouble then
              HasDouble := True
            else
              HasFloat := True;
            if LandrixXmlDoubleIsNaN(ItemDouble(A.Items[I])) and (NaNAt < 0) then
              NaNAt := I;
          end
        end;
        { xs:duration and the Gregorian types have no order, not even
          with themselves; nor have the binary types in XPath 2.0 (Saxon
          orders them) }
        for I := 0 to A.Count - 1 do
          if (A.Items[I].Kind in [xikDuration] + GregorianKinds) or Xp20 and (A.Items[I].Kind in BinaryKinds) then
            Fail('FORG0006', Name + ': ' + KindName(A.Items[I].Kind) + ' values have no order');
        { xs:anyURI among strings compares and returns as xs:string }
        Found := False;
        for I := 0 to A.Count - 1 do
          if BasicKind(A.Items[I].Kind) = xikString then
            Found := True;
        if Found then
          for I := 0 to A.Count - 1 do
            if A.Items[I].Kind = xikAnyUri then
              A.Items[I].Kind := xikString;
        { numbers are compared in their common type: xs:double if a double
          is there, else xs:float if a float is there (xs:integer stays, it
          is a decimal) }
        for I := 0 to A.Count - 1 do
          if IsNumeric(A.Items[I].Kind) then
          begin
            if HasDouble and (A.Items[I].Kind <> xikDouble) then
              A.Items[I] := DoubleItem(ToDouble(A.Items[I]))
            else if HasFloat and not HasDouble and (A.Items[I].Kind <> xikFloat) then
              A.Items[I] := FloatItem(ToFloat(A.Items[I], Xp20));
          end;
        K := 0;
        for I := 1 to A.Count - 1 do
        begin
          Item := A.Items[I];
          Acc := A.Items[K];
          try
            if (Id = xfnMin) and CompareAtomic(Item, Acc, xpcLt, Xp20, FImplicitTimeZone) or
              (Id = xfnMax) and CompareAtomic(Item, Acc, xpcGt, Xp20, FImplicitTimeZone) then
              K := I;
          except
            on E: ELandrixXmlXPathError do
            begin
              if E.XPathCode <> 'XPTY0004' then
                raise;
              Fail('FORG0006', Name + ': ' + KindName(Item.Kind) + ' and ' + KindName(Acc.Kind) +
                ' cannot be compared');
            end;
          end;
        end;
        { a NaN is the result, once every value has been converted and
          compared (type errors first) }
        if NaNAt >= 0 then
          K := NaNAt;
        Item := A.Items[K];
        if Item.Kind = xikUntypedAtomic then
          Item.Kind := xikString;
        Result := SingleSeq(Item);
      end;
    xfnString:
      begin
        if ArgCount = 0 then
          A := ContextSeq
        else
          A := Arg(0);
        if A.Count > 1 then
          Fail('XPTY0004', Name + ': more than one item');
        if A.Count = 0 then
          Result := LandrixXmlXPathStringItem('')
        else
          Result := LandrixXmlXPathStringItem(StringOf(A.Items[0]));
      end;
    xfnStringLength, xfnNormalizeSpace:
      begin
        if ArgCount = 0 then
        begin
          A := ContextSeq;
          S := StringOf(A.Items[0]);
        end
        else
          S := StrArg(0);
        if Id = xfnStringLength then
          Result := SingleSeq(IntegerItemOf(CodePointLength(S)))
        else
          Result := LandrixXmlXPathStringItem(NormalizeSpace(S));
      end;
    xfnConcat:
      begin
        S := '';
        for I := 0 to ArgCount - 1 do
          if OptAtom(I, Item) then
            S := S + AtomicString(Item);
        Result := LandrixXmlXPathStringItem(S);
      end;
    xfnStringJoin:
      begin
        A := Atomize(Arg(0));
        { XPath 2.0: xs:string* (untypedAtomic and anyURI become strings);
          Saxon joins any atomic values }
        if Xp20 then
          for I := 0 to A.Count - 1 do
            if not IsStringLike(A.Items[I].Kind) then
              Fail('XPTY0004', Name + ': ' + KindName(A.Items[I].Kind) + ' is not an xs:string');
        T := '';
        if ArgCount > 1 then
          T := ReqStrArg(1);
        S := '';
        for I := 0 to A.Count - 1 do
        begin
          if I > 0 then
            S := S + T;
          S := S + AtomicString(A.Items[I]);
        end;
        Result := LandrixXmlXPathStringItem(S);
      end;
    xfnSubstring:
      begin
        S := StrArg(0);
        Start := RoundedDouble(DoubleArg(1));
        if ArgCount > 2 then
          Stop := LandrixXmlDoubleAdd(Start, RoundedDouble(DoubleArg(2)))
        else
          Stop := Start;
        CPs := LandrixXmlUtf8ToCodePoints(S);
        J := 0;
        T := '';
        for I := 1 to Integer(Length(CPs)) do
          if InRange(I, Start, Stop, ArgCount > 2) then
          begin
            if J = 0 then
              J := I;
            K := I;
          end;
        if J > 0 then
          T := Copy(S, BytePosition(S, J), BytePosition(S, K + 1) - BytePosition(S, J));
        Result := LandrixXmlXPathStringItem(T);
      end;
    xfnSubstringBefore, xfnSubstringAfter:
      begin
        S := StrArg(0);
        T := StrArg(1);
        R := '';
        if T = '' then
        begin
          if Id = xfnSubstringAfter then
            R := S;
        end
        else
        begin
          I := Pos(T, S);
          if I > 0 then
          begin
            if Id = xfnSubstringBefore then
              R := Copy(S, 1, I - 1)
            else
              R := Copy(S, I + Length(T), MaxInt);
          end;
        end;
        Result := LandrixXmlXPathStringItem(R);
      end;
    xfnContains:
      begin
        S := StrArg(0);
        T := StrArg(1);
        Result := BooleanSeq((T = '') or (Pos(T, S) > 0));
      end;
    xfnStartsWith:
      begin
        S := StrArg(0);
        T := StrArg(1);
        Result := BooleanSeq(Copy(S, 1, Length(T)) = T);
      end;
    xfnEndsWith:
      begin
        S := StrArg(0);
        T := StrArg(1);
        Result := BooleanSeq((Length(T) <= Length(S)) and (Copy(S, Length(S) - Length(T) + 1, Length(T)) = T));
      end;
    xfnUpperCase:
      Result := LandrixXmlXPathStringItem(MapCase(StrArg(0), True));
    xfnLowerCase:
      Result := LandrixXmlXPathStringItem(MapCase(StrArg(0), False));
    xfnTranslate:
      begin
        CPs := LandrixXmlUtf8ToCodePoints(StrArg(0));
        Map := LandrixXmlUtf8ToCodePoints(ReqStrArg(1));
        Trans := LandrixXmlUtf8ToCodePoints(ReqStrArg(2));
        Len := 0;
        for I := 0 to Integer(Length(CPs)) - 1 do
        begin
          K := -1;
          for J := 0 to Integer(Length(Map)) - 1 do
            if Map[J] = CPs[I] then
            begin
              K := J;
              Break;
            end;
          if K < 0 then
          begin
            CPs[Len] := CPs[I];
            Inc(Len);
          end
          else if K < Length(Trans) then
          begin
            CPs[Len] := Trans[K];
            Inc(Len);
          end;
        end;
        SetLength(CPs, Len);
        Result := LandrixXmlXPathStringItem(LandrixXmlCodePointsToUtf8(CPs, 0, Integer(Length(CPs))));
      end;
    xfnMatches:
      begin
        S := StrArg(0);
        Re := Compile(1, 2);
        Result := BooleanSeq(Re.Matches(S));
      end;
    xfnReplace:
      begin
        S := StrArg(0);
        Re := Compile(1, 3);
        T := ReqStrArg(2);
        if Re.MatchesEmptyString then
          Fail('FORX0003', Name + ': the pattern matches the empty string');
        try
          Result := LandrixXmlXPathStringItem(Re.Replace(S, T));
        except
          on E: ELandrixXmlError do
          begin
            if E is ELandrixXmlXPathError then
              raise;
            Fail('FORX0004', Name + ': ' + E.Message);
          end;
        end;
      end;
    xfnTokenize:
      begin
        S := StrArg(0);
        Re := Compile(1, 2);
        if S = '' then
          Exit;
        if Re.MatchesEmptyString then
          Fail('FORX0003', Name + ': the pattern matches the empty string');
        Parts := Re.Tokenize(S);
        for I := 0 to Integer(Length(Parts)) - 1 do
          LandrixXmlXPathAppend(Result, StringItem(xikString, Parts[I]));
      end;
    xfnStringToCodepoints:
      begin
        CPs := LandrixXmlUtf8ToCodePoints(StrArg(0));
        for I := 0 to Integer(Length(CPs)) - 1 do
          LandrixXmlXPathAppend(Result, IntegerItemOf(CPs[I]));
      end;
    xfnCodepointsToString:
      begin
        A := Atomize(Arg(0));
        CPs := nil;
        SetLength(CPs, A.Count);
        for I := 0 to A.Count - 1 do
        begin
          Item := A.Items[I];
          if Item.Kind = xikUntypedAtomic then
            Item := CastTo(Item, xikInteger, Xp20);
          if BasicKind(Item.Kind) <> xikInteger then
            Fail('XPTY0004', Name + ': ' + KindName(Item.Kind) + ' is not an integer');
          if not LandrixXmlDecimalTryToInt64(ItemDecimal(Item), V64) or (V64 < 1) or (V64 > $10FFFF) or
            not LandrixXmlIsXmlChar(Cardinal(V64)) then
            Fail('FOCH0001', Name + ': ' + LandrixXmlUtf8ToString(LandrixXmlFormatDecimal(ItemDecimal(Item))) +
              ' is not an XML character');
          CPs[I] := Integer(V64);
        end;
        Result := LandrixXmlXPathStringItem(LandrixXmlCodePointsToUtf8(CPs, 0, Integer(Length(CPs))));
      end;
    xfnNumber:
      begin
        if ArgCount = 0 then
          A := Atomize(ContextSeq)
        else
          A := Atomize(Arg(0));
        if A.Count > 1 then
          Fail('XPTY0004', Name + ': more than one item');
        if A.Count = 0 then
          Result := SingleSeq(DoubleItem(LandrixXmlDoubleNaN))
        else
        begin
          try
            Result := SingleSeq(CastTo(A.Items[0], xikDouble, Xp20));
          except
            on E: ELandrixXmlXPathError do
            begin
              if (E.XPathCode <> 'FORG0001') and (E.XPathCode <> 'XPTY0004') then
                raise;
              Result := SingleSeq(DoubleItem(LandrixXmlDoubleNaN));
            end;
          end;
        end;
      end;
    xfnAbs, xfnRound, xfnRoundHalfToEven, xfnFloor, xfnCeiling:
      begin
        if not OptAtom(0, Item) then
          Exit;
        { the argument as it was }
        Acc := Item;
        Item := NumericKind(Item);
        K := 0;
        if (Id in [xfnRound, xfnRoundHalfToEven]) and (ArgCount > 1) then
          K := IntArg(1);
        { far below the value's digits the result is 0 either way }
        if K < -100000 then
          K := -100000;
        if Item.Kind = xikFloat then
          case Id of
            xfnAbs: Item := FloatItem(LandrixXmlDoubleAbs(ItemDouble(Item)));
            xfnRound: Item := FloatItem(RoundFloat(ItemDouble(Item), K, xdrHalfCeiling, Xp20));
            xfnRoundHalfToEven: Item := FloatItem(RoundFloat(ItemDouble(Item), K, xdrHalfEven, Xp20));
            xfnFloor: Item := FloatItem(RoundFloat(ItemDouble(Item), 0, xdrFloor, Xp20));
          else
            Item := FloatItem(RoundFloat(ItemDouble(Item), 0, xdrCeiling, Xp20));
          end
        else if Item.Kind = xikDouble then
          case Id of
            xfnAbs: Item := DoubleItem(LandrixXmlDoubleAbs(ItemDouble(Item)));
            xfnRound: Item := DoubleItem(LandrixXmlDoubleRound(ItemDouble(Item), K, xdrHalfCeiling));
            xfnRoundHalfToEven: Item := DoubleItem(LandrixXmlDoubleRound(ItemDouble(Item), K, xdrHalfEven));
            xfnFloor: Item := DoubleItem(LandrixXmlDoubleRound(ItemDouble(Item), 0, xdrFloor));
          else
            Item := DoubleItem(LandrixXmlDoubleRound(ItemDouble(Item), 0, xdrCeiling));
          end
        else
          case Id of
            xfnAbs: Item := DecimalKindItem(Item.Kind, LandrixXmlDecimalAbs(ItemDecimal(Item)));
            xfnRound:
              if (Item.Kind = xikDecimal) or (K < 0) then
                Item := DecimalKindItem(Item.Kind, LandrixXmlDecimalRound(ItemDecimal(Item), K, xdrHalfCeiling));
            xfnRoundHalfToEven:
              if (Item.Kind = xikDecimal) or (K < 0) then
                Item := DecimalKindItem(Item.Kind, LandrixXmlDecimalRound(ItemDecimal(Item), K, xdrHalfEven));
            xfnFloor: Item := DecimalKindItem(Item.Kind, LandrixXmlDecimalRound(ItemDecimal(Item), 0, xdrFloor));
          else
            Item := DecimalKindItem(Item.Kind, LandrixXmlDecimalRound(ItemDecimal(Item), 0, xdrCeiling));
          end;
        { an argument of a type derived from xs:integer: XPath 2.0 returns an
          xs:integer, Saxon (checked with values from documents) the argument
          itself: floor and ceiling always, round with a precision of at least
          0, for 0 or, beyond Int64, if the value stays, round-half-to-even if
          the value stays (in Int64 and not 0: with a precision from -15 on),
          abs if it is positive }
        if not Xp20 and (Acc.Kind in IntegerKinds) then
        begin
          case Id of
            xfnFloor, xfnCeiling: Found := True;
            xfnRound:
              Found := (K >= 0) or (LandrixXmlDecimalSign(ItemDecimal(Acc)) = 0) or
                (not LandrixXmlDecimalTryToInt64(ItemDecimal(Acc), V64) and
                (LandrixXmlDecimalCompare(ItemDecimal(Acc), ItemDecimal(Item)) = 0));
            xfnRoundHalfToEven:
              Found := (LandrixXmlDecimalCompare(ItemDecimal(Acc), ItemDecimal(Item)) = 0) and
                ((K >= -15) or (LandrixXmlDecimalSign(ItemDecimal(Acc)) = 0) or
                not LandrixXmlDecimalTryToInt64(ItemDecimal(Acc), V64));
          else
            Found := LandrixXmlDecimalSign(ItemDecimal(Acc)) > 0;
          end;
          if Found then
            Item := Acc;
        end;
        Result := SingleSeq(Item);
      end;
    xfnName, xfnLocalName, xfnNamespaceUri:
      begin
        I := NodeArg;
        S := '';
        if I >= 0 then
        begin
          OwnTree := TreeOf(I, K);
          case Id of
            xfnName: S := OwnTree.NameUtf8(I - K);
            xfnLocalName: S := OwnTree.LocalNameUtf8(I - K);
          else
            S := OwnTree.NamespaceUriUtf8(I - K);
          end;
        end;
        if Id = xfnNamespaceUri then
          Result := SingleSeq(StringItem(xikAnyUri, S))
        else
          Result := LandrixXmlXPathStringItem(S);
      end;
    xfnRoot:
      begin
        I := NodeArg;
        if I >= 0 then
          Result := LandrixXmlXPathNodeItem(RootOf(I));
      end;
    xfnPosition, xfnLast:
      begin
        if Position <= 0 then
          Fail('XPDY0002', Name + ': no context');
        if Id = xfnPosition then
          Result := SingleSeq(IntegerItemOf(Position))
        else
          Result := SingleSeq(IntegerItemOf(Size));
      end;
    xfnReverse:
      begin
        A := Arg(0);
        for I := A.Count - 1 downto 0 do
          LandrixXmlXPathAppend(Result, A.Items[I]);
      end;
    xfnDistinctValues:
      begin
        A := Atomize(Arg(0));
        for I := 0 to A.Count - 1 do
        begin
          Found := False;
          for J := 0 to Result.Count - 1 do
            if SameValue(A.Items[I], Result.Items[J], True) then
            begin
              Found := True;
              Break;
            end;
          if not Found then
            LandrixXmlXPathAppend(Result, A.Items[I]);
        end;
      end;
    xfnSubsequence:
      begin
        A := Arg(0);
        Start := RoundedDouble(DoubleArg(1));
        if ArgCount > 2 then
          Stop := LandrixXmlDoubleAdd(Start, RoundedDouble(DoubleArg(2)))
        else
          Stop := Start;
        for I := 1 to A.Count do
          if InRange(I, Start, Stop, ArgCount > 2) then
            LandrixXmlXPathAppend(Result, A.Items[I - 1]);
      end;
    xfnIndexOf:
      begin
        A := Atomize(Arg(0));
        B := Atomize(Arg(1));
        if B.Count <> 1 then
          Fail('XPTY0004', Name + ': the search value must be a single item');
        for I := 0 to A.Count - 1 do
          if SameValue(A.Items[I], B.Items[0], False) then
            LandrixXmlXPathAppend(Result, IntegerItemOf(Int64(I) + 1));
      end;
    xfnData:
      Result := Atomize(Arg(0));
    xfnExactlyOne, xfnZeroOrOne, xfnOneOrMore:
      begin
        A := Arg(0);
        if (Id = xfnExactlyOne) and (A.Count <> 1) then
          Fail('FORG0005', Name + ': not exactly one item');
        if (Id = xfnZeroOrOne) and (A.Count > 1) then
          Fail('FORG0003', Name + ': more than one item');
        if (Id = xfnOneOrMore) and (A.Count = 0) then
          Fail('FORG0004', Name + ': no item');
        Result := A;
      end;
    xfnCurrent:
      begin
        if FCurrentNode < 0 then
          Fail('XPDY0002', Name + ': no current node');
        Result := LandrixXmlXPathNodeItem(FCurrentNode);
      end;
    xfnDocument:
      { the XSLT function with one argument: a URI AddDocument knows }
      if OptAtom(0, Item) then
      begin
        S := StringOf(Item);
        I := 0;
        while (I < Integer(Length(FDocUris))) and (FDocUris[I] <> S) do
          Inc(I);
        if I >= Integer(Length(FDocUris)) then
          Fail('FODC0002', Name + ': the document ' + LandrixXmlUtf8ToString(S) + ' is not available');
        Result := LandrixXmlXPathNodeItem(FDocBases[I]);
      end;
    xfnYearsFromDuration .. xfnSecondsFromDuration:
      if OptAtom(0, Item) then
      begin
        if Item.Kind = xikUntypedAtomic then
          Item := CastTo(Item, xikDuration, Xp20);
        if not (Item.Kind in DurationKinds) then
          Fail('XPTY0004', Name + ': ' + KindName(Item.Kind) + ' is not a duration');
        Result := SingleSeq(DurationComponent(Item, Id));
      end;
    xfnYearFromDateTime .. xfnTimezoneFromTime:
      if OptAtom(0, Item) then
      begin
        case Id of
          xfnYearFromDateTime .. xfnTimezoneFromDateTime: T2 := xikDateTime;
          xfnYearFromDate .. xfnTimezoneFromDate: T2 := xikDate;
        else
          T2 := xikTime;
        end;
        if Item.Kind = xikUntypedAtomic then
          Item := CastTo(Item, T2, Xp20);
        if Item.Kind <> T2 then
          Fail('XPTY0004', Name + ': ' + KindName(Item.Kind) + ' is not ' + KindName(T2));
        if Id in [xfnTimezoneFromDateTime, xfnTimezoneFromDate, xfnTimezoneFromTime] then
        begin
          if ItemDateTime(Item).HasTimeZone then
            Result := SingleSeq(DurationItem(xikDayTimeDuration, LandrixXmlDecimalZero,
              LandrixXmlDecimalFromInt64(Int64(ItemDateTime(Item).TimeZone) * 60)));
        end
        else
          Result := SingleSeq(DateComponent(Item, Id, Xp20));
      end;
    xfnAdjustDateTimeToTimezone, xfnAdjustDateToTimezone, xfnAdjustTimeToTimezone:
      if OptAtom(0, Item) then
      begin
        case Id of
          xfnAdjustDateTimeToTimezone: T2 := xikDateTime;
          xfnAdjustDateToTimezone: T2 := xikDate;
        else
          T2 := xikTime;
        end;
        if Item.Kind = xikUntypedAtomic then
          Item := CastTo(Item, T2, Xp20);
        if Item.Kind <> T2 then
          Fail('XPTY0004', Name + ': ' + KindName(Item.Kind) + ' is not ' + KindName(T2));
        if ArgCount = 1 then
          Result := SingleSeq(AdjustToTimeZone(Item, True, FImplicitTimeZone))
        else if not OptAtom(1, Acc) then
          Result := SingleSeq(AdjustToTimeZone(Item, False, 0))
        else
        begin
          if Acc.Kind = xikUntypedAtomic then
            Acc := CastTo(Acc, xikDayTimeDuration, Xp20);
          if Acc.Kind <> xikDayTimeDuration then
            Fail('XPTY0004', Name + ': the time zone must be an xs:dayTimeDuration');
          { whole minutes from -PT14H to PT14H }
          if not LandrixXmlDecimalTryToInt64(ItemSeconds(Acc), V64) or (V64 mod 60 <> 0) or (V64 > 50400) or
            (V64 < -50400) or not LandrixXmlDecimalIsInteger(ItemSeconds(Acc)) then
            Fail('FODT0003', Name + ': invalid time zone ' + LandrixXmlUtf8ToString(Acc.Text));
          Result := SingleSeq(AdjustToTimeZone(Item, True, Integer(V64 div 60)));
        end;
      end;
    xfnDateTime:
      begin
        Found := OptAtom(0, Item);
        if OptAtom(1, Acc) and Found then
        begin
          if Item.Kind = xikUntypedAtomic then
            Item := CastTo(Item, xikDate, Xp20);
          if Acc.Kind = xikUntypedAtomic then
            Acc := CastTo(Acc, xikTime, Xp20);
          if (Item.Kind <> xikDate) or (Acc.Kind <> xikTime) then
            Fail('XPTY0004', Name + ': an xs:date and an xs:time are expected');
          Result := SingleSeq(CombineDateTime(Item, Acc));
        end;
      end;
    xfnCurrentDateTime:
      Result := SingleSeq(ClockItem(xikDateTime));
    xfnCurrentDate:
      Result := SingleSeq(ClockItem(xikDate));
    xfnCurrentTime:
      Result := SingleSeq(ClockItem(xikTime));
    xfnImplicitTimezone:
      Result := SingleSeq(DurationItem(xikDayTimeDuration, LandrixXmlDecimalZero,
        LandrixXmlDecimalFromInt64(Int64(FImplicitTimeZone) * 60)));
    xfnXsString, xfnXsBoolean, xfnXsDecimal, xfnXsInteger, xfnXsDouble, xfnXsFloat, xfnXsDate,
    xfnXsDateTime, xfnXsTime, xfnXsAnyUri, xfnXsUntypedAtomic, xfnXsNonPositiveInteger .. xfnXsPositiveInteger,
    xfnXsNormalizedString .. xfnXsENTITY, xfnXsDuration .. xfnXsDayTimeDuration,
    xfnXsGYearMonth .. xfnXsBase64Binary:
      begin
        if not OptAtom(0, Item) then
          Exit;
        case Id of
          xfnXsString: Result := SingleSeq(CastTo(Item, xikString, Xp20));
          xfnXsBoolean: Result := SingleSeq(CastTo(Item, xikBoolean, Xp20));
          xfnXsDecimal: Result := SingleSeq(CastTo(Item, xikDecimal, Xp20));
          xfnXsInteger: Result := SingleSeq(CastTo(Item, xikInteger, Xp20));
          xfnXsDouble: Result := SingleSeq(CastTo(Item, xikDouble, Xp20));
          xfnXsFloat: Result := SingleSeq(CastTo(Item, xikFloat, Xp20));
          xfnXsDate: Result := SingleSeq(CastTo(Item, xikDate, Xp20));
          xfnXsDateTime: Result := SingleSeq(CastTo(Item, xikDateTime, Xp20));
          xfnXsTime: Result := SingleSeq(CastTo(Item, xikTime, Xp20));
          xfnXsAnyUri: Result := SingleSeq(CastTo(Item, xikAnyUri, Xp20));
          xfnXsUntypedAtomic: Result := SingleSeq(CastTo(Item, xikUntypedAtomic, Xp20));
          xfnXsNonPositiveInteger .. xfnXsPositiveInteger, xfnXsNormalizedString .. xfnXsENTITY,
          xfnXsDuration .. xfnXsDayTimeDuration, xfnXsGYearMonth .. xfnXsBase64Binary:
            Result := SingleSeq(CastTo(Item, FNodes[Index].AtomicType, Xp20));
        else
          { every constructor function is listed above }
        end;
      end;
  end;
end;
