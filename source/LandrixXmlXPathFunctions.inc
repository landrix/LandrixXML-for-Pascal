{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXPathEval: the built-in functions, with the argument
  rules of XPath 3.1 as Saxon 12 applies them (concat and string-join take
  any atomic values), and the conversion of user function arguments.
  Included at the end of the implementation section. }

function TLandrixXmlXPathEvaluator.ConvertTo(const S: TLandrixXmlXPathSequence;
  const T: TLandrixXmlXPathSequenceType; const FunctionName: string): TLandrixXmlXPathSequence;
var
  I: Integer;
  Item: TLandrixXmlXPathItem;
  A: TLandrixXmlXPathSequence;
  Ok: Boolean;
begin
  if not T.Declared or (T.Kind = xtkAnyItem) then
    Result := S
  else if T.Kind = xtkNode then
  begin
    for I := 0 to S.Count - 1 do
      if S.Items[I].Kind <> xikNode then
        Fail('XPTY0004', FunctionName + ': a node was expected');
    Result := S;
  end
  else
  begin
    A := Atomize(S);
    Result := LandrixXmlXPathEmpty;
    for I := 0 to A.Count - 1 do
    begin
      Item := A.Items[I];
      if (Item.Kind = xikUntypedAtomic) and (T.AtomicType <> xatAnyAtomic) and (T.AtomicType <> xatUntypedAtomic) then
        Item := CastTo(Item, T.AtomicType)
      else
      begin
        { promotions: integer and decimal to double, anyURI to string }
        Ok := True;
        case T.AtomicType of
          xatAnyAtomic: ;
          xatString:
            if Item.Kind = xikAnyUri then
              Item := StringItem(xikString, Item.Text)
            else
              Ok := Item.Kind = xikString;
          xatUntypedAtomic: Ok := Item.Kind = xikUntypedAtomic;
          xatBoolean: Ok := Item.Kind = xikBoolean;
          xatDecimal: Ok := Item.Kind in [xikInteger, xikDecimal];
          xatInteger: Ok := Item.Kind = xikInteger;
          xatDouble:
            if Item.Kind in [xikInteger, xikDecimal] then
              Item := DoubleItem(LandrixXmlDoubleFromDecimal(Item.Decimal))
            else
              Ok := Item.Kind = xikDouble;
          xatDate: Ok := Item.Kind = xikDate;
          xatDateTime: Ok := Item.Kind = xikDateTime;
          xatTime: Ok := Item.Kind = xikTime;
          xatAnyUri: Ok := Item.Kind = xikAnyUri;
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
  Found, HasDouble: Boolean;
  Name: string;

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
    V := NumericOperand(V);
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
      V := CastTo(V, xatInteger);
    if V.Kind <> xikInteger then
      Fail('XPTY0004', Name + ': argument ' + IntToStr(K + 1) + ' must be an integer');
    if not LandrixXmlDecimalTryToInt64(V.Decimal, I64) or (I64 > High(Integer)) or (I64 < Low(Integer)) then
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
    Result := NumericOperand(V);
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
      if (P.Kind = xikDouble) and (Q.Kind = xikDouble) and LandrixXmlDoubleIsNaN(P.DoubleValue) and
        LandrixXmlDoubleIsNaN(Q.DoubleValue) then
      begin
        Result := NaNEqual;
        Exit;
      end;
      Result := CompareNumbers(P, Q) = 0;
    end
    else if IsStringLike(P.Kind) and IsStringLike(Q.Kind) then
      Result := P.Text = Q.Text
    else if (P.Kind = xikBoolean) and (Q.Kind = xikBoolean) then
      Result := P.BooleanValue = Q.BooleanValue
    else if (P.Kind in [xikDate, xikDateTime, xikTime]) and (P.Kind = Q.Kind) then
    begin
      try
        Result := CompareDates(P, Q) = 0;
      except
        on ELandrixXmlXPathError do
          Result := False;
      end;
    end
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
        if not IsNumeric(A.Items[0].Kind) and (A.Items[0].Kind <> xikUntypedAtomic) then
          Fail('FORG0006', Name + ': ' + KindName(A.Items[0].Kind) + ' is not a number');
        Acc := NumericOperand(A.Items[0]);
        for I := 1 to A.Count - 1 do
        begin
          Item := A.Items[I];
          if not IsNumeric(Item.Kind) and (Item.Kind <> xikUntypedAtomic) then
            Fail('FORG0006', Name + ': ' + KindName(Item.Kind) + ' is not a number');
          Acc := Arithmetic(Acc, Item, xpaAdd);
        end;
        if Id = xfnAvg then
          Acc := Arithmetic(Acc, IntegerItemOf(A.Count), xpaDivide);
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
        for I := 0 to A.Count - 1 do
        begin
          if A.Items[I].Kind = xikUntypedAtomic then
            A.Items[I] := DoubleItem(ParseDouble(A.Items[I].Text));
          if A.Items[I].Kind = xikDouble then
          begin
            HasDouble := True;
            if LandrixXmlDoubleIsNaN(A.Items[I].DoubleValue) then
            begin
              Result := SingleSeq(A.Items[I]);
              Exit;
            end;
          end
        end;
        { xs:anyURI among strings compares and returns as xs:string }
        Found := False;
        for I := 0 to A.Count - 1 do
          if A.Items[I].Kind = xikString then
            Found := True;
        if Found then
          for I := 0 to A.Count - 1 do
            if A.Items[I].Kind = xikAnyUri then
              A.Items[I].Kind := xikString;
        K := 0;
        for I := 1 to A.Count - 1 do
        begin
          Item := A.Items[I];
          Acc := A.Items[K];
          try
            if (Id = xfnMin) and CompareAtomic(Item, Acc, xpcLt) or (Id = xfnMax) and CompareAtomic(Item, Acc, xpcGt) then
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
        Item := A.Items[K];
        { promoted to xs:double if a double is there (xs:integer stays, it is
          a decimal) }
        if IsNumeric(Item.Kind) then
        begin
          if HasDouble and (Item.Kind <> xikDouble) then
            Item := DoubleItem(ToDouble(Item));
        end
        else if Item.Kind = xikUntypedAtomic then
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
            Item := CastTo(Item, xatInteger);
          if Item.Kind <> xikInteger then
            Fail('XPTY0004', Name + ': ' + KindName(Item.Kind) + ' is not an integer');
          if not LandrixXmlDecimalTryToInt64(Item.Decimal, V64) or (V64 < 1) or (V64 > $10FFFF) or
            not LandrixXmlIsXmlChar(Cardinal(V64)) then
            Fail('FOCH0001', Name + ': ' + LandrixXmlUtf8ToString(LandrixXmlFormatDecimal(Item.Decimal)) +
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
            Result := SingleSeq(CastTo(A.Items[0], xatDouble));
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
        Item := NumericKind(Item);
        K := 0;
        if (Id in [xfnRound, xfnRoundHalfToEven]) and (ArgCount > 1) then
          K := IntArg(1);
        { far below the value's digits the result is 0 either way }
        if K < -100000 then
          K := -100000;
        if Item.Kind = xikDouble then
          case Id of
            xfnAbs: Item.DoubleValue := LandrixXmlDoubleAbs(Item.DoubleValue);
            xfnRound: Item.DoubleValue := LandrixXmlDoubleRound(Item.DoubleValue, K, xdrHalfCeiling);
            xfnRoundHalfToEven: Item.DoubleValue := LandrixXmlDoubleRound(Item.DoubleValue, K, xdrHalfEven);
            xfnFloor: Item.DoubleValue := LandrixXmlDoubleRound(Item.DoubleValue, 0, xdrFloor);
          else
            Item.DoubleValue := LandrixXmlDoubleRound(Item.DoubleValue, 0, xdrCeiling);
          end
        else
          case Id of
            xfnAbs: Item.Decimal := LandrixXmlDecimalAbs(Item.Decimal);
            xfnRound:
              if (Item.Kind = xikDecimal) or (K < 0) then
                Item.Decimal := LandrixXmlDecimalRound(Item.Decimal, K, xdrHalfCeiling);
            xfnRoundHalfToEven:
              if (Item.Kind = xikDecimal) or (K < 0) then
                Item.Decimal := LandrixXmlDecimalRound(Item.Decimal, K, xdrHalfEven);
            xfnFloor: Item.Decimal := LandrixXmlDecimalRound(Item.Decimal, 0, xdrFloor);
          else
            Item.Decimal := LandrixXmlDecimalRound(Item.Decimal, 0, xdrCeiling);
          end;
        Result := SingleSeq(Item);
      end;
    xfnName, xfnLocalName, xfnNamespaceUri:
      begin
        I := NodeArg;
        S := '';
        if I >= 0 then
          case Id of
            xfnName: S := FTree.NameUtf8(I);
            xfnLocalName: S := FTree.LocalNameUtf8(I);
          else
            S := FTree.NamespaceUriUtf8(I);
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
          Result := LandrixXmlXPathNodeItem(0);
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
    xfnXsString, xfnXsBoolean, xfnXsDecimal, xfnXsInteger, xfnXsDouble, xfnXsFloat, xfnXsDate,
    xfnXsDateTime, xfnXsTime, xfnXsAnyUri, xfnXsUntypedAtomic:
      begin
        if not OptAtom(0, Item) then
          Exit;
        case Id of
          xfnXsString: Result := SingleSeq(CastTo(Item, xatString));
          xfnXsBoolean: Result := SingleSeq(CastTo(Item, xatBoolean));
          xfnXsDecimal: Result := SingleSeq(CastTo(Item, xatDecimal));
          xfnXsInteger: Result := SingleSeq(CastTo(Item, xatInteger));
          xfnXsDouble: Result := SingleSeq(CastTo(Item, xatDouble));
          xfnXsDate: Result := SingleSeq(CastTo(Item, xatDate));
          xfnXsDateTime: Result := SingleSeq(CastTo(Item, xatDateTime));
          xfnXsTime: Result := SingleSeq(CastTo(Item, xatTime));
          xfnXsAnyUri: Result := SingleSeq(CastTo(Item, xatAnyUri));
          xfnXsUntypedAtomic: Result := SingleSeq(CastTo(Item, xatUntypedAtomic));
        else
          Fail('FOER0000', 'xs:float is not supported');
        end;
      end;
  end;
end;
