{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Regular expressions in the dialects of XML Schema (pattern facet) and
  XPath (fn:matches, fn:replace, fn:tokenize), for the validation units.

  Matching works on Unicode code points with a Pike VM (a Thompson NFA
  simulation that keeps the priority of alternatives and greedy
  quantifiers), so one match takes time linear in the input for every
  pattern: untrusted documents cannot trigger catastrophic backtracking.
  Replace and Tokenize search again after every match, so a pattern whose
  match attempts run to the end of the input can take quadratic time
  there, as with Saxon. Matches are leftmost-first, as with a backtracking
  engine such as Saxon's. Compiled programs are limited to about 100000
  instructions and groups and class subtractions to a nesting depth of
  1000 (ELandrixXmlError with xecLimit).

  Supported: alternation, groups (xrmXPath also non-capturing (?:...)),
  the quantifiers ? * + and counted repetitions (n; n or more; n to m),
  '.', character class expressions with ranges, negation and subtraction,
  the escapes \n \r \t, \\ and the other single-character escapes,
  \s \S \i \I \c \C \d \D \w \W, the category escapes \p and \P with a
  category name such as L or Lu (Unicode 6.2.0, as Saxon); in XPath mode
  ^ and $
  (start and end of the string). XSD patterns match the whole string, and
  ^ and $ are ordinary characters there.
  Not supported (ELandrixXmlError with xecUnsupported, never silently
  ignored): flags, reluctant quantifiers, back-references, block escapes
  (\p with IsBasicLatin and the like). Invalid patterns raise xecRegex.

  A hyphen in a character class follows XML Schema 1.0 in the modes XSD
  (as Xerces) and XPath 2.0: a literal hyphen only at the start or end of
  the class (or before a subtraction). In the mode xrmXPath it follows
  XML Schema 1.1 and XPath 3.1, as Saxon: a hyphen after a range or a class escape, or
  before ']' or '-[', is a literal, but two unescaped hyphens in a row
  are only allowed before '['. In both modes a range cannot start or end
  with an unescaped hyphen.

  Known differences from Saxon: a group inside a repetition keeps the
  text of the last non-empty iteration ("(a*)+b" on "aaab" gives "aaa"
  for group 1, Saxon an empty string), and the category Cs is not
  known (Saxon has no table for it either, and UTF-8 input never
  contains surrogates). }

unit LandrixXmlRegex;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlUnicode;

type
  TLandrixXmlRegexMode = (
    xrmXsd,    { XML Schema pattern facet: the whole string must match }
    xrmXPath,  { fn:matches and friends as Saxon (XPath 3.1): a match
                 anywhere, ^ and $ anchors, (?:...) groups, the
                 character classes of XML Schema 1.1 }
    xrmXPath20 { XPath 2.0: as xrmXPath, but no (?:...) groups and the
                 character classes of XML Schema 1.0 }
  );

  { Internal compiled forms, public only because Delphi 6 has no nested
    types. }
  TLandrixXmlRegexOp = (xroSet, xroSplit, xroJump, xroSave, xroStart, xroEnd, xroMatch);
  TLandrixXmlRegexInstr = record
    Op: TLandrixXmlRegexOp;
    A: Integer; { set index, save slot, or relative target }
    B: Integer; { second relative target of xroSplit }
  end;
  TLandrixXmlRegexCode = array of TLandrixXmlRegexInstr;
  { Sorted disjoint code point ranges: Lo0, Hi0, Lo1, Hi1, ... }
  TLandrixXmlRegexSet = array of Integer;

  TLandrixXmlRegex = class
  private
    FMode: TLandrixXmlRegexMode;
    FPattern: TLandrixXmlCodePoints;
    FPos: Integer;
    FSets: array of TLandrixXmlRegexSet;
    FSetCount: Integer;
    FCode: TLandrixXmlRegexCode;
    FGroupCount: Integer;
    FMatchesEmpty: Boolean;
    FSource: TLandrixXmlUtf8;
    FDepth: Integer;
    procedure Error(const Msg: string);
    procedure Nest;
    procedure Unsupported(const Msg: string);
    function AtEnd: Boolean;
    function Peek: Integer;
    function PeekAt(Offset: Integer): Integer;
    function AddSet(const S: TLandrixXmlRegexSet): Integer;
    function ParseRegExp: TLandrixXmlRegexCode;
    function ParseBranch: TLandrixXmlRegexCode;
    function ParsePiece: TLandrixXmlRegexCode;
    function ParseAtom: TLandrixXmlRegexCode;
    function ParseQuantity(out Min, Max: Integer): Boolean;
    function ParseClassExpr: TLandrixXmlRegexSet;
    function ParseEscape(out CodePoint: Integer): TLandrixXmlRegexSet;
    function ParseCategory(Negated: Boolean): TLandrixXmlRegexSet;
  public
    { Compiles Pattern. Flags must be empty (no flag is supported yet). }
    constructor Create(const Pattern: TLandrixXmlUtf8; Mode: TLandrixXmlRegexMode;
      const Flags: TLandrixXmlUtf8 = '');
    { XSD mode: True if the whole of S matches. XPath mode: True if the
      pattern matches somewhere in S (fn:matches). }
    function Matches(const S: TLandrixXmlUtf8): Boolean;
    { fn:replace: every non-overlapping match, leftmost first, replaced by
      Replacement, in which $N stands for group N (the longest number not
      above GroupCount, a single digit if GroupCount is below 10 as with
      Saxon; an unmatched group gives '') and \$ and \\ for $
      and \. Raises xecRegex if the pattern matches the empty string or
      the replacement is invalid. }
    function Replace(const S, Replacement: TLandrixXmlUtf8): TLandrixXmlUtf8;
    { fn:tokenize: the parts of S between matches (an empty S gives no
      part). Raises xecRegex if S is not empty and the pattern matches the
      empty string. }
    function Tokenize(const S: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
    property GroupCount: Integer read FGroupCount;
    { True if the pattern matches the empty string (fn:replace and
      fn:tokenize then raise FORX0003). }
    property MatchesEmptyString: Boolean read FMatchesEmpty;
    property Mode: TLandrixXmlRegexMode read FMode;
    property Source: TLandrixXmlUtf8 read FSource;
  end;

implementation

const
  MaxCodePoint = $10FFFF;
  { Limit of the compiled program; counted repetitions are written out. }
  MaxInstructions = 100000;
  { Limit of nested groups and class subtractions (recursive parser). }
  MaxDepth = 1000;
  Unbounded = -1;

  CharTab = 9;
  CharLf = 10;
  CharCr = 13;

{ ---------------------------------------------------------------------- }
{ Code point sets                                                        }
{ ---------------------------------------------------------------------- }

function SetRange(Lo, Hi: Integer): TLandrixXmlRegexSet;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0] := Lo;
  Result[1] := Hi;
end;

{ Sorts the ranges by Lo and merges overlapping or adjacent ones. }
procedure SetNormalize(var S: TLandrixXmlRegexSet);
var
  I, J, N, Lo, Hi: Integer;
begin
  N := Integer(Length(S)) div 2;
  { insertion sort: the sets are small or already sorted }
  for I := 1 to N - 1 do
  begin
    Lo := S[2 * I];
    Hi := S[2 * I + 1];
    J := I - 1;
    while (J >= 0) and (S[2 * J] > Lo) do
    begin
      S[2 * J + 2] := S[2 * J];
      S[2 * J + 3] := S[2 * J + 1];
      Dec(J);
    end;
    S[2 * J + 2] := Lo;
    S[2 * J + 3] := Hi;
  end;
  J := -1;
  for I := 0 to N - 1 do
  begin
    if (J >= 0) and (S[2 * I] <= S[2 * J + 1] + 1) then
    begin
      if S[2 * I + 1] > S[2 * J + 1] then
        S[2 * J + 1] := S[2 * I + 1];
    end
    else
    begin
      Inc(J);
      S[2 * J] := S[2 * I];
      S[2 * J + 1] := S[2 * I + 1];
    end;
  end;
  SetLength(S, 2 * (J + 1));
end;

function SetUnion(const A, B: TLandrixXmlRegexSet): TLandrixXmlRegexSet;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A) + Length(B));
  for I := 0 to Integer(Length(A)) - 1 do
    Result[I] := A[I];
  for I := 0 to Integer(Length(B)) - 1 do
    Result[Integer(Length(A)) + I] := B[I];
  SetNormalize(Result);
end;

{ Complement within 0 .. U+10FFFF; S must be normalized. }
function SetComplement(const S: TLandrixXmlRegexSet): TLandrixXmlRegexSet;
var
  I, N, Next: Integer;
begin
  Result := nil;
  SetLength(Result, Length(S) + 2);
  N := 0;
  Next := 0;
  I := 0;
  while I < Length(S) do
  begin
    if S[I] > Next then
    begin
      Result[N] := Next;
      Result[N + 1] := S[I] - 1;
      Inc(N, 2);
    end;
    Next := S[I + 1] + 1;
    Inc(I, 2);
  end;
  if Next <= MaxCodePoint then
  begin
    Result[N] := Next;
    Result[N + 1] := MaxCodePoint;
    Inc(N, 2);
  end;
  SetLength(Result, N);
end;

{ A without B; both normalized. }
function SetSubtract(const A, B: TLandrixXmlRegexSet): TLandrixXmlRegexSet;
var
  C: TLandrixXmlRegexSet;
  I, J, N, Lo, Hi: Integer;
begin
  { A and (not B) by a merge of the two sorted range lists }
  C := SetComplement(B);
  Result := nil;
  SetLength(Result, Length(A) + Length(C));
  N := 0;
  I := 0;
  J := 0;
  while (I < Length(A)) and (J < Length(C)) do
  begin
    if A[I] > C[J] then
      Lo := A[I]
    else
      Lo := C[J];
    if A[I + 1] < C[J + 1] then
      Hi := A[I + 1]
    else
      Hi := C[J + 1];
    if Lo <= Hi then
    begin
      Result[N] := Lo;
      Result[N + 1] := Hi;
      Inc(N, 2);
    end;
    if A[I + 1] < C[J + 1] then
      Inc(I, 2)
    else
      Inc(J, 2);
  end;
  SetLength(Result, N);
end;

function SetContains(const S: TLandrixXmlRegexSet; CodePoint: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Lo := 0;
  Hi := Integer(Length(S)) div 2 - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) div 2;
    if CodePoint < S[2 * Mid] then
      Hi := Mid - 1
    else if CodePoint > S[2 * Mid + 1] then
      Lo := Mid + 1
    else
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function SetFromCategories(Categories: TLandrixXmlUnicodeCategories): TLandrixXmlRegexSet;
var
  I, N, Lo, Hi: Integer;
  Category: TLandrixXmlUnicodeCategory;
  AssignedSet: TLandrixXmlRegexSet;
begin
  { Delphi 6 warns about managed locals assigned in one branch only }
  AssignedSet := nil;
  Result := nil;
  SetLength(Result, 2 * LandrixXmlUnicodeRangeCount);
  N := 0;
  for I := 0 to LandrixXmlUnicodeRangeCount - 1 do
  begin
    LandrixXmlUnicodeRange(I, Lo, Hi, Category);
    if Category in Categories then
    begin
      Result[N] := Lo;
      Result[N + 1] := Hi;
      Inc(N, 2);
    end;
  end;
  SetLength(Result, N);
  SetNormalize(Result);
  if xucCn in Categories then
  begin
    { unassigned code points are the gaps of the table }
    AssignedSet := SetFromCategories([Low(TLandrixXmlUnicodeCategory)..High(TLandrixXmlUnicodeCategory)] -
      [xucCn]);
    Result := SetUnion(Result, SetComplement(AssignedSet));
  end;
end;

{ XML 1.0 fifth edition NameStartChar (\i) and NameChar (\c), as
  LandrixXmlIsNameStartChar and LandrixXmlIsNameChar. }
function SetNameStart: TLandrixXmlRegexSet;
const
  R: array[0..31] of Integer = (Ord(':'), Ord(':'), Ord('A'), Ord('Z'), Ord('_'), Ord('_'),
    Ord('a'), Ord('z'), $C0, $D6, $D8, $F6, $F8, $2FF, $370, $37D, $37F, $1FFF, $200C, $200D,
    $2070, $218F, $2C00, $2FEF, $3001, $D7FF, $F900, $FDCF, $FDF0, $FFFD, $10000, $EFFFF);
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(R));
  for I := 0 to High(R) do
    Result[I] := R[I];
  SetNormalize(Result);
end;

function SetNameChar: TLandrixXmlRegexSet;
const
  R: array[0..9] of Integer = (Ord('-'), Ord('.'), Ord('0'), Ord('9'), $B7, $B7,
    $300, $36F, $203F, $2040);
var
  Extra: TLandrixXmlRegexSet;
  I: Integer;
begin
  Extra := nil;
  SetLength(Extra, Length(R));
  for I := 0 to High(R) do
    Extra[I] := R[I];
  SetNormalize(Extra);
  Result := SetUnion(SetNameStart, Extra);
end;

{ ---------------------------------------------------------------------- }
{ Code fragments (relative jumps, so they can be copied)                 }
{ ---------------------------------------------------------------------- }

type
  TLandrixXmlRegexCodeList = array of TLandrixXmlRegexCode;

function Instr(Op: TLandrixXmlRegexOp; A, B: Integer): TLandrixXmlRegexCode;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].Op := Op;
  Result[0].A := A;
  Result[0].B := B;
end;

procedure RaiseTooLarge;
begin
  raise ELandrixXmlError.CreateCode(xecLimit, 'Regular expression too large');
end;

{ Makes room for Extra more instructions after Dest[0 .. Count - 1],
  growing Dest geometrically so that appending stays linear. }
procedure Reserve(var Dest: TLandrixXmlRegexCode; Count, Extra: Integer);
begin
  if Int64(Count) + Extra > MaxInstructions then
    RaiseTooLarge;
  if Count + Extra > Length(Dest) then
    SetLength(Dest, 2 * (Count + Extra));
end;

procedure AppendInstr(var Dest: TLandrixXmlRegexCode; var Count: Integer; Op: TLandrixXmlRegexOp;
  A, B: Integer);
begin
  Reserve(Dest, Count, 1);
  Dest[Count].Op := Op;
  Dest[Count].A := A;
  Dest[Count].B := B;
  Inc(Count);
end;

procedure AppendCode(var Dest: TLandrixXmlRegexCode; var Count: Integer; const Src: TLandrixXmlRegexCode);
var
  I: Integer;
begin
  Reserve(Dest, Count, Integer(Length(Src)));
  for I := 0 to Integer(Length(Src)) - 1 do
    Dest[Count + I] := Src[I];
  Inc(Count, Integer(Length(Src)));
end;

{ A repeated Min to Max times, Max = Unbounded for no upper limit. The size
  is known in advance, so an oversized repetition fails before any copy. }
function Repeated(const A: TLandrixXmlRegexCode; Min, Max: Integer): TLandrixXmlRegexCode;
var
  I, Len, Count, TailEnd: Integer;
  Total: Int64;
begin
  Result := nil;
  Len := Integer(Length(A));
  if Max = Unbounded then
    Total := Int64(Min) * Len + Len + 2
  else
    Total := Int64(Min) * Len + (Int64(Max) - Min) * (Int64(Len) + 1);
  if Total > MaxInstructions then
    RaiseTooLarge;
  SetLength(Result, Integer(Total));
  Count := 0;
  for I := 1 to Min do
    AppendCode(Result, Count, A);
  if Max = Unbounded then
  begin
    { A*, greedy: split, A, jump back to the split }
    AppendInstr(Result, Count, xroSplit, 1, Len + 2);
    AppendCode(Result, Count, A);
    AppendInstr(Result, Count, xroJump, -(Len + 1), 0);
  end
  else
  begin
    { optional copies, nested so that each one is only tried after the
      previous one matched: (A(A(A)?)?)?; every split skips to the end }
    TailEnd := Count + (Max - Min) * (Len + 1);
    for I := Min + 1 to Max do
    begin
      AppendInstr(Result, Count, xroSplit, 1, TailEnd - Count);
      AppendCode(Result, Count, A);
    end;
  end;
end;

{ ---------------------------------------------------------------------- }
{ Pike VM                                                                }
{ ---------------------------------------------------------------------- }

type
  TThread = record
    PC: Integer;
    Captures: TLandrixXmlCodePoints;
  end;
  TThreadArray = array of TThread;
  TThreadList = record
    Items: TThreadArray;
    Count: Integer;
  end;
  { The working memory of a run; Replace and Tokenize keep it for all
    their runs, so the marks are allocated once per call. Each run and
    each step uses a new Generation, so old marks never need clearing. }
  TVmState = record
    Marks: array of Integer;
    Generation: Integer;
    Stack: TThreadArray;
    StackCount: Integer;
    Current, Next: TThreadList;
    WantCaptures: Boolean;
  end;

procedure InitVm(R: TLandrixXmlRegex; out State: TVmState; WantCaptures: Boolean);
var
  I: Integer;
begin
  State.Marks := nil;
  SetLength(State.Marks, Length(R.FCode));
  for I := 0 to Integer(Length(R.FCode)) - 1 do
    State.Marks[I] := -1;
  State.Generation := 0;
  State.Stack := nil;
  State.StackCount := 0;
  State.Current.Items := nil;
  State.Current.Count := 0;
  State.Next.Items := nil;
  State.Next.Count := 0;
  State.WantCaptures := WantCaptures;
end;

procedure Push(var State: TVmState; PC: Integer; const Captures: TLandrixXmlCodePoints);
begin
  if State.StackCount = Length(State.Stack) then
    SetLength(State.Stack, 2 * State.StackCount + 16);
  State.Stack[State.StackCount].PC := PC;
  State.Stack[State.StackCount].Captures := Captures;
  Inc(State.StackCount);
end;

{ Follows the jumps, splits, saves and assertions from PC and adds the
  threads that wait for a character (or match) to List, in priority
  order. Depth first with an explicit stack: a recursive walk would need
  stack space in proportion to the program. }
procedure AddThread(const Code: TLandrixXmlRegexCode; var State: TVmState; var List: TThreadList;
  StartPC: Integer; const StartCaptures: TLandrixXmlCodePoints; Position, TextLength: Integer);
var
  PC, I: Integer;
  Captures, Copied: TLandrixXmlCodePoints;
begin
  Copied := nil;
  Captures := nil;
  Push(State, StartPC, StartCaptures);
  while State.StackCount > 0 do
  begin
    Dec(State.StackCount);
    PC := State.Stack[State.StackCount].PC;
    Captures := State.Stack[State.StackCount].Captures;
    State.Stack[State.StackCount].Captures := nil;
    if State.Marks[PC] = State.Generation then
      Continue;
    State.Marks[PC] := State.Generation;
    case Code[PC].Op of
      xroJump:
        Push(State, PC + Code[PC].A, Captures);
      xroSplit:
        begin
          { the preferred target is taken from the stack first }
          Push(State, PC + Code[PC].B, Captures);
          Push(State, PC + Code[PC].A, Captures);
        end;
      xroSave:
        if State.WantCaptures then
        begin
          Copied := nil;
          SetLength(Copied, Length(Captures));
          for I := 0 to Integer(Length(Captures)) - 1 do
            Copied[I] := Captures[I];
          Copied[Code[PC].A] := Position;
          Push(State, PC + 1, Copied);
        end
        else
          Push(State, PC + 1, Captures);
      xroStart:
        if Position = 0 then
          Push(State, PC + 1, Captures);
      xroEnd:
        if Position = TextLength then
          Push(State, PC + 1, Captures);
    else
      { xroSet, xroMatch: wait for the next step }
      if List.Count = Length(List.Items) then
        SetLength(List.Items, 2 * List.Count + 8);
      List.Items[List.Count].PC := PC;
      List.Items[List.Count].Captures := Captures;
      Inc(List.Count);
    end;
  end;
end;

function RunVm(R: TLandrixXmlRegex; var State: TVmState; const Text: TLandrixXmlCodePoints;
  StartPos: Integer; Search: Boolean; out Captures: TLandrixXmlCodePoints): Boolean;
var
  Swap: TThreadList;
  Position, TextLength, I, J: Integer;
  Initial: TLandrixXmlCodePoints;
begin
  Result := False;
  Captures := nil;
  TextLength := Integer(Length(Text));
  Initial := nil;
  if State.WantCaptures then
  begin
    SetLength(Initial, 2 * R.FGroupCount + 2);
    for I := 0 to Integer(Length(Initial)) - 1 do
      Initial[I] := -1;
  end;
  State.Current.Count := 0;
  State.Next.Count := 0;
  Inc(State.Generation);
  Position := StartPos;
  while True do
  begin
    { a new attempt at Position has the lowest priority; none once a
      match is known, because matches are leftmost }
    if (Position = StartPos) or (Search and not Result) then
      AddThread(R.FCode, State, State.Current, 0, Initial, Position, TextLength);
    { no thread left: done, unless a search can still start further on }
    if (State.Current.Count = 0) and (Result or not Search) then
      Break;
    Inc(State.Generation);
    State.Next.Count := 0;
    for I := 0 to State.Current.Count - 1 do
    begin
      J := State.Current.Items[I].PC;
      if R.FCode[J].Op = xroMatch then
      begin
        Result := True;
        Captures := State.Current.Items[I].Captures;
        if not State.WantCaptures then
          Exit;
        { threads of lower priority are dropped }
        Break;
      end;
      { xroSet }
      if (Position < TextLength) and SetContains(R.FSets[R.FCode[J].A], Text[Position]) then
        AddThread(R.FCode, State, State.Next, J + 1, State.Current.Items[I].Captures, Position + 1,
          TextLength);
    end;
    if Position >= TextLength then
      Break;
    Swap := State.Current;
    State.Current := State.Next;
    State.Next := Swap;
    Inc(Position);
    if (State.Current.Count = 0) and (Result or not Search) then
      Break;
  end;
end;

{ ---------------------------------------------------------------------- }
{ Parser                                                                 }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlRegex.Create(const Pattern: TLandrixXmlUtf8; Mode: TLandrixXmlRegexMode;
  const Flags: TLandrixXmlUtf8 = '');
var
  Body: TLandrixXmlRegexCode;
  Empty: TLandrixXmlCodePoints;
  Captures: TLandrixXmlCodePoints;
  Count: Integer;
  State: TVmState;
begin
  inherited Create;
  FMode := Mode;
  FSource := Pattern;
  if Flags <> '' then
    Unsupported('regular expression flags');
  FPattern := LandrixXmlUtf8ToCodePoints(Pattern);
  FPos := 0;
  Body := ParseRegExp;
  if not AtEnd then
    Error('unmatched ")"');
  { group 0 spans the whole match; an XSD pattern is anchored at the end }
  FCode := nil;
  Count := 0;
  AppendInstr(FCode, Count, xroSave, 0, 0);
  AppendCode(FCode, Count, Body);
  if FMode = xrmXsd then
    AppendInstr(FCode, Count, xroEnd, 0, 0);
  AppendInstr(FCode, Count, xroSave, 1, 0);
  AppendInstr(FCode, Count, xroMatch, 0, 0);
  SetLength(FCode, Count);
  Empty := nil;
  InitVm(Self, State, False);
  FMatchesEmpty := RunVm(Self, State, Empty, 0, False, Captures);
end;

procedure TLandrixXmlRegex.Error(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecRegex, 'Invalid regular expression "' +
    LandrixXmlEscapeForMessage(FSource, 60) + '": ' + Msg + ' at character ' + IntToStr(FPos + 1));
end;

{ Called on entering a group or a class subtraction; the parser is
  recursive, so the depth must stay well within the stack. }
procedure TLandrixXmlRegex.Nest;
begin
  Inc(FDepth);
  if FDepth > MaxDepth then
    raise ELandrixXmlError.CreateCode(xecLimit, 'Regular expression nested too deeply');
end;

procedure TLandrixXmlRegex.Unsupported(const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecUnsupported, 'Regular expression "' +
    LandrixXmlEscapeForMessage(FSource, 60) + '": not supported: ' + Msg);
end;

function TLandrixXmlRegex.AtEnd: Boolean;
begin
  Result := FPos >= Length(FPattern);
end;

function TLandrixXmlRegex.Peek: Integer;
begin
  if FPos < Length(FPattern) then
    Result := FPattern[FPos]
  else
    Result := -1;
end;

function TLandrixXmlRegex.PeekAt(Offset: Integer): Integer;
begin
  if FPos + Offset < Length(FPattern) then
    Result := FPattern[FPos + Offset]
  else
    Result := -1;
end;

function TLandrixXmlRegex.AddSet(const S: TLandrixXmlRegexSet): Integer;
begin
  if FSetCount = Length(FSets) then
    SetLength(FSets, 2 * FSetCount + 8);
  FSets[FSetCount] := S;
  Result := FSetCount;
  Inc(FSetCount);
end;

{ Branches B1 | B2 | ... | Bn as split, B1, jump to the end, split, B2,
  ..., Bn: each split prefers its branch over the rest. }
function TLandrixXmlRegex.ParseRegExp: TLandrixXmlRegexCode;
var
  Branches: TLandrixXmlRegexCodeList;
  N, I, Count, Total, Finish: Integer;
begin
  Branches := nil;
  N := 0;
  Total := 0;
  repeat
    if N > 0 then
      Inc(FPos); { '|' }
    if N = Length(Branches) then
      SetLength(Branches, 2 * N + 4);
    Branches[N] := ParseBranch;
    Inc(Total, Integer(Length(Branches[N])) + 2);
    if Total > MaxInstructions then
      RaiseTooLarge;
    Inc(N);
  until Peek <> Ord('|');
  if N = 1 then
  begin
    Result := Branches[0];
    Exit;
  end;
  Result := nil;
  Finish := Total - 2;
  SetLength(Result, Finish);
  Count := 0;
  for I := 0 to N - 2 do
  begin
    AppendInstr(Result, Count, xroSplit, 1, Integer(Length(Branches[I])) + 2);
    AppendCode(Result, Count, Branches[I]);
    AppendInstr(Result, Count, xroJump, Finish - Count, 0);
  end;
  AppendCode(Result, Count, Branches[N - 1]);
end;

function TLandrixXmlRegex.ParseBranch: TLandrixXmlRegexCode;
var
  Count: Integer;
begin
  Result := nil;
  Count := 0;
  while not AtEnd and (Peek <> Ord('|')) and (Peek <> Ord(')')) do
    AppendCode(Result, Count, ParsePiece);
  SetLength(Result, Count);
end;

{ Reads a number of at most 9 digits; False if there is no digit. }
function ReadNumber(const P: TLandrixXmlCodePoints; var Position: Integer; out Value: Integer): Boolean;
var
  Digits: Integer;
begin
  Value := 0;
  Digits := 0;
  while (Position < Length(P)) and (P[Position] >= Ord('0')) and (P[Position] <= Ord('9')) do
  begin
    if Digits < 9 then
      Value := Value * 10 + (P[Position] - Ord('0'))
    else
      Value := MaxInt; { far beyond MaxInstructions }
    Inc(Digits);
    Inc(Position);
  end;
  Result := Digits > 0;
end;

function TLandrixXmlRegex.ParseQuantity(out Min, Max: Integer): Boolean;
var
  C: Integer;
begin
  Result := True;
  C := Peek;
  Min := 1;
  Max := 1;
  if C = Ord('?') then
  begin
    Min := 0;
    Max := 1;
  end
  else if C = Ord('*') then
  begin
    Min := 0;
    Max := Unbounded;
  end
  else if C = Ord('+') then
  begin
    Min := 1;
    Max := Unbounded;
  end
  else if C = Ord('{') then
  begin
    Inc(FPos);
    if not ReadNumber(FPattern, FPos, Min) then
      Error('number expected in quantifier');
    if Peek = Ord(',') then
    begin
      Inc(FPos);
      if not ReadNumber(FPattern, FPos, Max) then
        Max := Unbounded
      else if Max < Min then
        Error('quantifier {n,m} with m < n');
    end
    else
      Max := Min;
    if Peek <> Ord('}') then
      Error('"}" expected');
  end
  else
  begin
    Result := False;
    Exit;
  end;
  Inc(FPos);
  if (Min > MaxInstructions) or (Max > MaxInstructions) then
    raise ELandrixXmlError.CreateCode(xecLimit, 'Regular expression quantifier too large');
end;

function TLandrixXmlRegex.ParsePiece: TLandrixXmlRegexCode;
var
  Atom: TLandrixXmlRegexCode;
  Min, Max, Dummy1, Dummy2: Integer;
begin
  Atom := ParseAtom;
  if not ParseQuantity(Min, Max) then
  begin
    Result := Atom;
    Exit;
  end;
  if (FMode <> xrmXsd) and (Peek = Ord('?')) then
    Unsupported('reluctant quantifier');
  if ParseQuantity(Dummy1, Dummy2) then
    Error('quantifier follows a quantifier');
  Result := Repeated(Atom, Min, Max);
end;

function TLandrixXmlRegex.ParseAtom: TLandrixXmlRegexCode;
var
  C, Group, CodePoint, Count: Integer;
  S: TLandrixXmlRegexSet;
begin
  Result := nil;
  Count := 0;
  C := Peek;
  case C of
    Ord('('):
      begin
        Inc(FPos);
        Nest;
        if Peek = Ord('?') then
        begin
          if (FMode = xrmXPath) and (PeekAt(1) = Ord(':')) then
          begin
            Inc(FPos, 2);
            Result := ParseRegExp;
          end
          else
            Error('"(?" is not allowed');
        end
        else
        begin
          Inc(FGroupCount);
          Group := FGroupCount;
          AppendInstr(Result, Count, xroSave, 2 * Group, 0);
          AppendCode(Result, Count, ParseRegExp);
          AppendInstr(Result, Count, xroSave, 2 * Group + 1, 0);
          SetLength(Result, Count);
        end;
        if Peek <> Ord(')') then
          Error('")" expected');
        Inc(FPos);
        Dec(FDepth);
      end;
    Ord('['):
      Result := Instr(xroSet, AddSet(ParseClassExpr), 0);
    Ord('.'):
      begin
        Inc(FPos);
        S := nil;
        SetLength(S, 4);
        S[0] := CharLf;
        S[1] := CharLf;
        S[2] := CharCr;
        S[3] := CharCr;
        SetNormalize(S);
        Result := Instr(xroSet, AddSet(SetComplement(S)), 0);
      end;
    Ord('\'):
      begin
        S := ParseEscape(CodePoint);
        Result := Instr(xroSet, AddSet(S), 0);
      end;
    Ord('?'), Ord('*'), Ord('+'), Ord('{'), Ord('}'), Ord(']'), Ord(')'), Ord('|'):
      Error('unexpected "' + Char(C) + '"');
  else
    if (FMode <> xrmXsd) and (C = Ord('^')) then
    begin
      Inc(FPos);
      Result := Instr(xroStart, 0, 0);
    end
    else if (FMode <> xrmXsd) and (C = Ord('$')) then
    begin
      Inc(FPos);
      Result := Instr(xroEnd, 0, 0);
    end
    else
    begin
      Inc(FPos);
      Result := Instr(xroSet, AddSet(SetRange(C, C)), 0);
    end;
  end;
end;

{ An escape starting at '\'. CodePoint = the character for a single-character
  escape (it may then be the end of a range), else -1. }
function TLandrixXmlRegex.ParseEscape(out CodePoint: Integer): TLandrixXmlRegexSet;
var
  C: Integer;
  S: TLandrixXmlRegexSet;
begin
  Result := nil;
  CodePoint := -1;
  Inc(FPos); { the backslash }
  if AtEnd then
    Error('"\" at the end');
  C := Peek;
  Inc(FPos);
  case C of
    Ord('n'): CodePoint := CharLf;
    Ord('r'): CodePoint := CharCr;
    Ord('t'): CodePoint := CharTab;
    Ord('\'), Ord('|'), Ord('.'), Ord('?'), Ord('*'), Ord('+'), Ord('('), Ord(')'), Ord('{'),
    Ord('}'), Ord('-'), Ord('['), Ord(']'), Ord('^'):
      CodePoint := C;
    Ord('$'):
      if FMode <> xrmXsd then
        CodePoint := C
      else
        Error('unknown escape "\$"');
    Ord('s'), Ord('S'):
      begin
        S := nil;
        SetLength(S, 8);
        S[0] := CharTab; S[1] := CharTab;
        S[2] := CharLf; S[3] := CharLf;
        S[4] := CharCr; S[5] := CharCr;
        S[6] := Ord(' '); S[7] := Ord(' ');
        SetNormalize(S);
        if C = Ord('S') then
          S := SetComplement(S);
        Result := S;
      end;
    Ord('i'):
      Result := SetNameStart;
    Ord('I'):
      Result := SetComplement(SetNameStart);
    Ord('c'):
      Result := SetNameChar;
    Ord('C'):
      Result := SetComplement(SetNameChar);
    Ord('d'):
      Result := SetFromCategories([xucNd]);
    Ord('D'):
      Result := SetComplement(SetFromCategories([xucNd]));
    Ord('w'):
      Result := SetComplement(SetFromCategories(LandrixXmlCategoriesP + LandrixXmlCategoriesZ +
        LandrixXmlCategoriesC));
    Ord('W'):
      Result := SetFromCategories(LandrixXmlCategoriesP + LandrixXmlCategoriesZ +
        LandrixXmlCategoriesC);
    Ord('p'):
      Result := ParseCategory(False);
    Ord('P'):
      Result := ParseCategory(True);
    Ord('1')..Ord('9'):
      if FMode <> xrmXsd then
        Unsupported('back-reference')
      else
        Error('unknown escape');
  else
    Error('unknown escape');
  end;
  if CodePoint >= 0 then
    Result := SetRange(CodePoint, CodePoint);
end;

function TLandrixXmlRegex.ParseCategory(Negated: Boolean): TLandrixXmlRegexSet;
var
  Name: string;
  C: Integer;
  Cats: TLandrixXmlUnicodeCategories;
  Major: Char;
begin
  if Peek <> Ord('{') then
    Error('"{" expected after \p');
  Inc(FPos);
  Name := '';
  while not AtEnd and (Peek <> Ord('}')) do
  begin
    C := Peek;
    if C > 127 then
      Error('invalid category name');
    Name := Name + Char(C);
    Inc(FPos);
  end;
  if AtEnd then
    Error('"}" expected');
  Inc(FPos);
  if Name = 'Is' then
    Error('block name expected after \p{Is');
  if Copy(Name, 1, 2) = 'Is' then
    Unsupported('block escape \p{' + Name + '}');
  Cats := [];
  if Length(Name) = 1 then
  begin
    Major := Name[1];
    case Major of
      'L': Cats := LandrixXmlCategoriesL;
      'M': Cats := LandrixXmlCategoriesM;
      'N': Cats := LandrixXmlCategoriesN;
      'P': Cats := LandrixXmlCategoriesP;
      'S': Cats := LandrixXmlCategoriesS;
      'Z': Cats := LandrixXmlCategoriesZ;
      'C': Cats := LandrixXmlCategoriesC;
    end;
  end
  else if Name = 'Lu' then Cats := [xucLu]
  else if Name = 'Ll' then Cats := [xucLl]
  else if Name = 'Lt' then Cats := [xucLt]
  else if Name = 'Lm' then Cats := [xucLm]
  else if Name = 'Lo' then Cats := [xucLo]
  else if Name = 'Mn' then Cats := [xucMn]
  else if Name = 'Mc' then Cats := [xucMc]
  else if Name = 'Me' then Cats := [xucMe]
  else if Name = 'Nd' then Cats := [xucNd]
  else if Name = 'Nl' then Cats := [xucNl]
  else if Name = 'No' then Cats := [xucNo]
  else if Name = 'Pc' then Cats := [xucPc]
  else if Name = 'Pd' then Cats := [xucPd]
  else if Name = 'Ps' then Cats := [xucPs]
  else if Name = 'Pe' then Cats := [xucPe]
  else if Name = 'Pi' then Cats := [xucPi]
  else if Name = 'Pf' then Cats := [xucPf]
  else if Name = 'Po' then Cats := [xucPo]
  else if Name = 'Zs' then Cats := [xucZs]
  else if Name = 'Zl' then Cats := [xucZl]
  else if Name = 'Zp' then Cats := [xucZp]
  else if Name = 'Sm' then Cats := [xucSm]
  else if Name = 'Sc' then Cats := [xucSc]
  else if Name = 'Sk' then Cats := [xucSk]
  else if Name = 'So' then Cats := [xucSo]
  else if Name = 'Cc' then Cats := [xucCc]
  else if Name = 'Cf' then Cats := [xucCf]
  else if Name = 'Co' then Cats := [xucCo]
  else if Name = 'Cn' then Cats := [xucCn];
  if Cats = [] then
    Error('unknown category \p{' + Name + '}');
  Result := SetFromCategories(Cats);
  if Negated then
    Result := SetComplement(Result);
end;

{ '[' ... ']' with negation and subtraction. }
function TLandrixXmlRegex.ParseClassExpr: TLandrixXmlRegexSet;
var
  Negated, First, PlainHyphen: Boolean;
  C, Lo, Hi, CodePoint: Integer;
  Part: TLandrixXmlRegexSet;
begin
  Part := nil;
  Inc(FPos); { '[' }
  Nest;
  Negated := False;
  if Peek = Ord('^') then
  begin
    Negated := True;
    Inc(FPos);
  end;
  Result := nil;
  First := True;
  while True do
  begin
    if AtEnd then
      Error('"]" expected');
    C := Peek;
    if C = Ord(']') then
    begin
      if First then
        Error('empty character class');
      Break;
    end;
    if (C = Ord('-')) and (PeekAt(1) = Ord('[')) then
    begin
      if First then
        Error('empty character class before subtraction');
      Break;
    end;
    if C = Ord('[') then
      Error('"[" must be escaped in a character class');
    { one item: a character, a range or a multi-character escape }
    if C = Ord('\') then
    begin
      Part := ParseEscape(CodePoint);
      Lo := CodePoint;
      PlainHyphen := False;
    end
    else
    begin
      { XML Schema 1.0: a hyphen inside the class must be escaped; 1.1
        and XPath take it literally where it cannot start a range }
      { the end of the positive group is also before a subtraction "-[",
        as XML Schema 1.0 (F.1) says; xrmXsd keeps Xerces' reading }
      if (FMode <> xrmXPath) and (C = Ord('-')) and not First and (PeekAt(1) <> Ord(']')) and
        not ((FMode = xrmXPath20) and (PeekAt(1) = Ord('-')) and (PeekAt(2) = Ord('['))) then
        Error('"-" must be escaped or stand at the start or end of a character class');
      Inc(FPos);
      Lo := C;
      PlainHyphen := C = Ord('-');
      Part := SetRange(C, C);
    end;
    { XPath, as Saxon: an unescaped hyphen may only be followed by
      another one that starts a subtraction }
    if (FMode = xrmXPath) and PlainHyphen and (Peek = Ord('-')) and (PeekAt(1) <> Ord('[')) then
      Error('"-" cannot follow an unescaped "-"');
    { a following '-' starts a range unless ']' or '[' follows, or in
      the XPath modes "-[" (then it is a literal before a subtraction) }
    if (Lo >= 0) and (Peek = Ord('-')) and (PeekAt(1) <> Ord(']')) and (PeekAt(1) <> Ord('[')) and
      not ((FMode <> xrmXsd) and (PeekAt(1) = Ord('-')) and (PeekAt(2) = Ord('['))) then
    begin
      if PlainHyphen then
        Error('a range cannot start with an unescaped "-"');
      Inc(FPos); { '-' }
      C := Peek;
      if C = Ord('\') then
      begin
        ParseEscape(CodePoint);
        if CodePoint < 0 then
          Error('a range cannot end with a multi-character escape');
        Hi := CodePoint;
      end
      else
      begin
        if (C = Ord('[')) or (C = Ord(']')) or (C = Ord('-')) or (C < 0) then
          Error('invalid end of range');
        Inc(FPos);
        Hi := C;
      end;
      if Hi < Lo then
        Error('range with end before start');
      Part := SetRange(Lo, Hi);
    end;
    Result := SetUnion(Result, Part);
    First := False;
  end;
  if Negated then
    Result := SetComplement(Result);
  if Peek = Ord('-') then
  begin
    Inc(FPos); { '-', then '[' follows }
    Result := SetSubtract(Result, ParseClassExpr);
  end;
  if Peek <> Ord(']') then
    Error('"]" expected after a subtraction');
  Inc(FPos);
  Dec(FDepth);
end;

function TLandrixXmlRegex.Matches(const S: TLandrixXmlUtf8): Boolean;
var
  Captures: TLandrixXmlCodePoints;
  State: TVmState;
begin
  InitVm(Self, State, False);
  Result := RunVm(Self, State, LandrixXmlUtf8ToCodePoints(S), 0, FMode <> xrmXsd, Captures);
end;

function TLandrixXmlRegex.Replace(const S, Replacement: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  Text, Rep, Captures: TLandrixXmlCodePoints;
  Buffer: TLandrixXmlBuffer;
  Position, I, Group, Digit: Integer;
  State: TVmState;
begin
  if FMatchesEmpty then
    raise ELandrixXmlError.CreateCode(xecRegex, 'Regular expression "' +
      LandrixXmlEscapeForMessage(FSource, 60) + '" matches a zero-length string');
  Text := LandrixXmlUtf8ToCodePoints(S);
  Rep := LandrixXmlUtf8ToCodePoints(Replacement);
  { validate the replacement once }
  I := 0;
  while I < Length(Rep) do
  begin
    if Rep[I] = Ord('\') then
    begin
      if (I + 1 >= Length(Rep)) or ((Rep[I + 1] <> Ord('\')) and (Rep[I + 1] <> Ord('$'))) then
        raise ELandrixXmlError.CreateCode(xecRegex, 'Invalid replacement string: "\" must be followed by "\" or "$"');
      Inc(I, 2);
    end
    else if Rep[I] = Ord('$') then
    begin
      if (I + 1 >= Length(Rep)) or (Rep[I + 1] < Ord('0')) or (Rep[I + 1] > Ord('9')) then
        raise ELandrixXmlError.CreateCode(xecRegex, 'Invalid replacement string: "$" must be followed by a digit');
      Inc(I, 2);
    end
    else
      Inc(I);
  end;
  InitVm(Self, State, True);
  Buffer := TLandrixXmlBuffer.Create;
  try
    Position := 0;
    while (Position <= Length(Text)) and RunVm(Self, State, Text, Position, True, Captures) do
    begin
      for I := Position to Captures[0] - 1 do
        Buffer.AppendCodePoint(Cardinal(Text[I]));
      I := 0;
      while I < Length(Rep) do
      begin
        if Rep[I] = Ord('\') then
        begin
          Buffer.AppendCodePoint(Cardinal(Rep[I + 1]));
          Inc(I, 2);
        end
        else if Rep[I] = Ord('$') then
        begin
          { the longest group number not above GroupCount (at least one
            digit); with fewer than ten groups one digit, as Saxon, so
            that "$01" is group 0 and a literal 1 }
          Group := Rep[I + 1] - Ord('0');
          Inc(I, 2);
          while (FGroupCount >= 10) and (I < Length(Rep)) and (Rep[I] >= Ord('0')) and (Rep[I] <= Ord('9')) do
          begin
            Digit := Rep[I] - Ord('0');
            if Group * 10 + Digit > FGroupCount then
              Break;
            Group := Group * 10 + Digit;
            Inc(I);
          end;
          if (Group <= FGroupCount) and (Captures[2 * Group] >= 0) and (Captures[2 * Group + 1] >= 0) then
            for Digit := Captures[2 * Group] to Captures[2 * Group + 1] - 1 do
              Buffer.AppendCodePoint(Cardinal(Text[Digit]));
        end
        else
        begin
          Buffer.AppendCodePoint(Cardinal(Rep[I]));
          Inc(I);
        end;
      end;
      if Captures[1] <= Captures[0] then
        raise ELandrixXmlError.CreateCode(xecRegex, 'Zero-length match in replace');
      Position := Captures[1];
    end;
    for I := Position to Integer(Length(Text)) - 1 do
      Buffer.AppendCodePoint(Cardinal(Text[I]));
    Result := Buffer.AsUtf8;
  finally
    Buffer.Free;
  end;
end;

function TLandrixXmlRegex.Tokenize(const S: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
var
  Text, Captures: TLandrixXmlCodePoints;
  Position, N: Integer;
  State: TVmState;
begin
  Result := nil;
  { an empty input gives no part, as with Saxon even for a pattern that
    matches the empty string }
  Text := LandrixXmlUtf8ToCodePoints(S);
  if Length(Text) = 0 then
    Exit;
  if FMatchesEmpty then
    raise ELandrixXmlError.CreateCode(xecRegex, 'Regular expression "' +
      LandrixXmlEscapeForMessage(FSource, 60) + '" matches a zero-length string');
  InitVm(Self, State, True);
  N := 0;
  Position := 0;
  while (Position <= Length(Text)) and RunVm(Self, State, Text, Position, True, Captures) do
  begin
    if N = Length(Result) then
      SetLength(Result, 2 * N + 4);
    Result[N] := LandrixXmlCodePointsToUtf8(Text, Position, Captures[0]);
    Inc(N);
    if Captures[1] <= Captures[0] then
      raise ELandrixXmlError.CreateCode(xecRegex, 'Zero-length match in tokenize');
    Position := Captures[1];
  end;
  if N = Length(Result) then
    SetLength(Result, N + 1);
  Result[N] := LandrixXmlCodePointsToUtf8(Text, Position, Integer(Length(Text)));
  SetLength(Result, N + 1);
end;

end.
