{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Schematron timing: loads a rule file and a document, validates it Count
  times and prints the times in milliseconds and the number of results.
  With "profile" it then runs every rule context and every check on its
  own (for rule files without global variables and functions, such as
  EN16931) and prints the slowest ones.

  Usage: LandrixXmlSchematronPerf RULES.xml DOCUMENT.xml [Count [profile]] }

program LandrixXmlSchematronPerf;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval,
  LandrixXmlSchematron;

function Ms(Start: TDateTime): Integer;
begin
  Result := Integer(Round((Now - Start) * 24 * 60 * 60 * 1000));
end;

{ the times as "milliseconds TAB what", slowest first }
function ByTime(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := StrToInt(Copy(List[Index2], 1, Pos(#9, List[Index2]) - 1)) -
    StrToInt(Copy(List[Index1], 1, Pos(#9, List[Index1]) - 1));
end;

procedure Profile(Rules: TLandrixXmlSchematronRules; Tree: TLandrixXmlXPathTree);
var
  E: TLandrixXmlXPathEvaluator;
  Times: TStringList;
  Pattern: TLandrixXmlSchematronPattern;
  Rule: TLandrixXmlSchematronRule;
  Check: TLandrixXmlSchematronCheck;
  First: array of Integer;
  Nodes: TLandrixXmlXPathSequence;
  P, R, K, J, Node, Slots, T: Integer;
  Start: TDateTime;
begin
  First := nil;
  Slots := 0;
  for P := 0 to Rules.PatternCount - 1 do
    for R := 0 to Integer(Rules.Patterns[P].Rules.Count) - 1 do
    begin
      Rule := TLandrixXmlSchematronRule(Rules.Patterns[P].Rules[R]);
      for J := 0 to Integer(Length(Rule.LetSlots)) - 1 do
        if Rule.LetSlots[J] >= Slots then
          Slots := Rule.LetSlots[J] + 1;
    end;
  Times := TStringList.Create;
  E := TLandrixXmlXPathEvaluator.Create(Tree);
  try
    E.SetGlobalCount(0);
    E.SetFrameSize(Slots);
    SetLength(First, Tree.Count);
    for P := 0 to Rules.PatternCount - 1 do
    begin
      Pattern := Rules.Patterns[P];
      for Node := 0 to Tree.Count - 1 do
        First[Node] := -1;
      for R := Integer(Pattern.Rules.Count) - 1 downto 0 do
      begin
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[R]);
        Start := Now;
        Nodes := E.EvaluateSequence(Rule.Context, 0);
        Times.Add(IntToStr(Ms(Start)) + #9'context ' + Rule.SourceLine + ' ' +
          LandrixXmlUtf8ToString(Rule.ContextText));
        for K := 0 to Nodes.Count - 1 do
          First[Nodes.Items[K].Node] := R;
      end;
      for R := 0 to Integer(Pattern.Rules.Count) - 1 do
      begin
        Rule := TLandrixXmlSchematronRule(Pattern.Rules[R]);
        for J := 0 to Integer(Rule.Checks.Count) - 1 do
        begin
          Check := TLandrixXmlSchematronCheck(Rule.Checks[J]);
          Start := Now;
          for Node := 0 to Tree.Count - 1 do
            if First[Node] = R then
            begin
              E.UnbindFrame;
              E.CurrentNode := Node;
              for K := 0 to Integer(Length(Rule.Lets)) - 1 do
                E.BindLazy(Rule.LetSlots[K], Rule.Lets[K], Node);
              try
                E.EvaluateBoolean(Check.Test, Node);
              except
                on ELandrixXmlXPathError do
                  ;
              end;
            end;
          Times.Add(IntToStr(Ms(Start)) + #9 + LandrixXmlUtf8ToString(Check.Id) + ' ' + Check.SourceLine);
        end;
      end;
    end;
    T := 0;
    for J := 0 to Times.Count - 1 do
      Inc(T, StrToInt(Copy(Times[J], 1, Pos(#9, Times[J]) - 1)));
    WriteLn('profile total: ', T, ' ms');
    Times.CustomSort(ByTime);
    for J := 0 to 24 do
      if J < Times.Count then
        WriteLn(Times[J]);
  finally
    E.Free;
    Times.Free;
  end;
end;

var
  Rules: TLandrixXmlSchematronRules;
  Tree: TLandrixXmlXPathTree;
  V: TLandrixXmlSchematronValidator;
  Start: TDateTime;
  I, Count, Best, T: Integer;

begin
  if ParamCount < 2 then
  begin
    WriteLn('Usage: LandrixXmlSchematronPerf RULES.xml DOCUMENT.xml [Count [profile]]');
    Halt(2);
  end;
  Count := 1;
  if ParamCount >= 3 then
    Count := StrToInt(ParamStr(3));
  Rules := TLandrixXmlSchematronRules.Create;
  Tree := TLandrixXmlXPathTree.Create;
  V := nil;
  try
    Start := Now;
    Rules.LoadFromFile(ParamStr(1));
    WriteLn('rules: ', Ms(Start), ' ms');
    Start := Now;
    Tree.LoadFromFile(ParamStr(2));
    WriteLn('tree: ', Ms(Start), ' ms, ', Tree.Count, ' nodes');
    V := TLandrixXmlSchematronValidator.Create(Rules);
    Best := MaxInt;
    for I := 1 to Count do
    begin
      Start := Now;
      V.ValidateTree(Tree);
      T := Ms(Start);
      if T < Best then
        Best := T;
    end;
    WriteLn('validate: ', Best, ' ms (best of ', Count, '), ', V.ResultCount, ' results');
    if (ParamCount >= 4) and (ParamStr(4) = 'profile') then
      Profile(Rules, Tree);
  finally
    V.Free;
    Tree.Free;
    Rules.Free;
  end;
end.
