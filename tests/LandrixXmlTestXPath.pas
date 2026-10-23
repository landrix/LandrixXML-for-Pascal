{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the XPath parser: the syntax tree of expressions (written as
  nested lists), name resolution and the static errors. }

unit LandrixXmlTestXPath;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble,
  LandrixXmlXPath,
  LandrixXmlTestFramework;

const
  AxisText: array[TLandrixXmlXPathAxis] of string = ('child', 'descendant', 'attribute', 'self',
    'descendant-or-self', 'following-sibling', 'parent', 'ancestor', 'preceding-sibling', 'preceding',
    'ancestor-or-self', 'following');
  CompareText: array[TLandrixXmlXPathCompare] of string = ('eq', 'ne', 'lt', 'le', 'gt', 'ge');
  ArithText: array[TLandrixXmlXPathArithmetic] of string = ('+', '-', '*', 'div', 'idiv', 'mod');

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function Dump(E: TLandrixXmlXPathExpression; Index: Integer): string;
var
  N: TLandrixXmlXPathAstNode;
  I: Integer;

  function Kids: string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to Integer(Length(N.Children)) - 1 do
      Result := Result + ' ' + Dump(E, N.Children[K]);
  end;

  function Preds: string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to Integer(Length(N.Predicates)) - 1 do
      Result := Result + '[' + Dump(E, N.Predicates[K]) + ']';
  end;

  function Test: string;
  begin
    case N.NodeTest of
      xntAnyNode: Result := 'node()';
      xntText: Result := 'text()';
      xntComment: Result := 'comment()';
      xntProcessingInstruction: Result := 'pi(' + LandrixXmlUtf8ToString(N.LocalName) + ')';
      xntDocumentNode: Result := 'document-node()';
      xntAnyElement: Result := 'element()';
      xntAnyAttribute: Result := 'attribute()';
      xntName: Result := '{' + LandrixXmlUtf8ToString(N.NamespaceUri) + '}' + LandrixXmlUtf8ToString(N.LocalName);
      xntNamespaceWildcard: Result := '{' + LandrixXmlUtf8ToString(N.NamespaceUri) + '}*';
      xntLocalWildcard: Result := '*:' + LandrixXmlUtf8ToString(N.LocalName);
    else
      Result := '*';
    end;
  end;

begin
  N := E.Nodes[Index];
  case N.Kind of
    xakSequence: Result := '(seq' + Kids + ')';
    xakEmpty: Result := '()';
    xakFor: Result := '(for' + Kids + ')';
    xakSome: Result := '(some' + Kids + ')';
    xakEvery: Result := '(every' + Kids + ')';
    xakIf: Result := '(if' + Kids + ')';
    xakOr: Result := '(or' + Kids + ')';
    xakAnd: Result := '(and' + Kids + ')';
    xakGeneralCompare: Result := '(=' + CompareText[TLandrixXmlXPathCompare(N.Op)] + Kids + ')';
    xakValueCompare: Result := '(' + CompareText[TLandrixXmlXPathCompare(N.Op)] + Kids + ')';
    xakRange: Result := '(to' + Kids + ')';
    xakArithmetic: Result := '(' + ArithText[TLandrixXmlXPathArithmetic(N.Op)] + Kids + ')';
    xakUnion: Result := '(|' + Kids + ')';
    xakIntersectExcept:
      if N.Op = 0 then
        Result := '(intersect' + Kids + ')'
      else
        Result := '(except' + Kids + ')';
    xakNodeCompare:
      case TLandrixXmlXPathCompare(N.Op) of
        xpcLt: Result := '(<<' + Kids + ')';
        xpcGt: Result := '(>>' + Kids + ')';
      else
        Result := '(is' + Kids + ')';
      end;
    xakNegate: Result := '(neg' + Kids + ')';
    xakUnaryPlus: Result := '(plus' + Kids + ')';
    xakCast, xakCastable:
      begin
        if N.Kind = xakCast then
          Result := '(cast'
        else
          Result := '(castable';
        Result := Result + Kids + ' ' + LandrixXmlXPathAtomicTypeName(N.AtomicType);
        if N.AllowEmpty then
          Result := Result + '?';
        Result := Result + ')';
      end;
    xakRoot: Result := '/';
    xakPath:
      begin
        if N.RootStart then
          Result := '(path/'
        else
          Result := '(path';
        Result := Result + Kids + ')';
      end;
    xakStep: Result := AxisText[N.Axis] + '::' + Test + Preds;
    xakFilter: Result := '(filter' + Kids + ')' + Preds;
    xakString: Result := '"' + LandrixXmlUtf8ToString(N.Text) + '"';
    xakInteger: Result := LandrixXmlUtf8ToString(LandrixXmlFormatDecimal(N.Decimal));
    xakDecimal: Result := LandrixXmlUtf8ToString(LandrixXmlFormatDecimal(N.Decimal)) + 'd';
    xakDouble: Result := LandrixXmlUtf8ToString(LandrixXmlDoubleFormat(N.DoubleValue)) + 'e';
    xakVariable: Result := '$' + IntToStr(N.Slot);
    xakContextItem: Result := '.';
    xakFunction:
      if N.Op < 0 then
        Result := '(user' + IntToStr(-1 - N.Op) + Kids + ')'
      else
        Result := '(' + LandrixXmlXPathFunctionName(TLandrixXmlXPathFunctionId(N.Op)) + Kids + ')';
  else
    Result := '?';
  end;
  for I := 0 to Integer(Length(N.Slots)) - 1 do
    Result := Result + ' $' + IntToStr(N.Slots[I]);
end;

var
  Context: TLandrixXmlXPathStaticContext;

procedure CheckParse(const Expr, Expected: string);
var
  E: TLandrixXmlXPathExpression;
begin
  E := nil;
  try
    try
      E := TLandrixXmlXPathExpression.Create(U(Expr), Context);
      CheckEqualsStr(Expected, Dump(E, E.Root), Expr);
    except
      on X: ELandrixXmlError do
        Check(False, Expr + ': ' + X.Message);
    end;
  finally
    E.Free;
  end;
end;

procedure CheckError(const Expr, Code: string);
var
  E: TLandrixXmlXPathExpression;
begin
  E := nil;
  try
    try
      E := TLandrixXmlXPathExpression.Create(U(Expr), Context);
      FailNotRaised(Code + ' for ' + Expr);
    except
      on X: ELandrixXmlXPathError do
      begin
        CheckEqualsStr(Code, X.XPathCode, Expr + ': ' + X.Message);
        CheckEquals(Ord(xecXPath), Ord(X.Code), Expr + ': error code');
      end;
      on X: ELandrixXmlError do
        Check(False, Expr + ': not an XPath error: ' + X.Message);
    end;
  finally
    E.Free;
  end;
end;

procedure SetUpContext;
begin
  Context.Free;
  Context := TLandrixXmlXPathStaticContext.Create;
  Context.AddNamespace(U('cbc'), U('urn:cbc'));
  Context.AddNamespace(U('cac'), U('urn:cac'));
  Context.AddNamespace(U('u'), U('utils'));
  Context.DeclareVariable(U('profile'));
  Context.DeclareVariable(U('XR-MAJOR-MINOR-VERSION'));
  Context.DeclareFunction(U('utils'), U('slack'), 3);
end;

procedure TestPaths;
begin
  SetUpContext;
  CheckParse('cbc:ID', 'child::{urn:cbc}ID');
  CheckParse('cac:Party/cbc:ID', '(path child::{urn:cac}Party child::{urn:cbc}ID)');
  CheckParse('/cac:Invoice', '(path/ child::{urn:cac}Invoice)');
  CheckParse('//cbc:ID', '(path/ descendant-or-self::node() child::{urn:cbc}ID)');
  CheckParse('a//b', '(path child::{}a descendant-or-self::node() child::{}b)');
  CheckParse('/', '/');
  CheckParse('../@currencyID', '(path parent::node() attribute::{}currencyID)');
  CheckParse('.', '.');
  CheckParse('*', 'child::*');
  CheckParse('cac:*', 'child::{urn:cac}*');
  CheckParse('*:ID', 'child::*:ID');
  CheckParse('/*/cbc:ProfileID', '(path/ child::* child::{urn:cbc}ProfileID)');
  CheckParse('ancestor::cac:Party[1]', 'ancestor::{urn:cac}Party[1]');
  CheckParse('self::node()', 'self::node()');
  CheckParse('text()', 'child::text()');
  CheckParse('preceding-sibling::*', 'preceding-sibling::*');
  CheckParse('attribute::x', 'attribute::{}x');
  CheckParse('cac:TaxCategory[cbc:ID = ''S''][1]',
    'child::{urn:cac}TaxCategory[(=eq child::{urn:cbc}ID "S")][1]');
  CheckParse('$profile/cbc:ID', '(path $0 child::{urn:cbc}ID)');
  CheckParse('(a, b)[1]', '(filter (seq child::{}a child::{}b))[1]');
  CheckParse('a/substring(b, 1, 2)', '(path child::{}a (substring child::{}b 1 2))');
  CheckParse('a/(b | c)', '(path child::{}a (| child::{}b child::{}c))');
  CheckParse('div', 'child::{}div');
  CheckParse('div div div', '(div child::{}div child::{}div)');
  CheckParse('processing-instruction(''x'')', 'child::pi(x)');
end;

procedure TestOperators;
begin
  SetUpContext;
  CheckParse('1 + 2 * 3', '(+ 1 (* 2 3))');
  CheckParse('a - b', '(- child::{}a child::{}b)');
  CheckParse('a-b', 'child::{}a-b');
  CheckParse('$XR-MAJOR-MINOR-VERSION', '$1');
  CheckParse('-1', '(neg 1)');
  CheckParse('- - 1', '(neg (neg 1))');
  CheckParse('1 div 2 idiv 3 mod 4', '(mod (idiv (div 1 2) 3) 4)');
  CheckParse('a = b and c != d or e', '(or (and (=eq child::{}a child::{}b) (=ne child::{}c child::{}d)) child::{}e)');
  CheckParse('a eq 1', '(eq child::{}a 1)');
  CheckParse('a le 1 and b >= 2', '(and (le child::{}a 1) (=ge child::{}b 2))');
  CheckParse('1 to 3', '(to 1 3)');
  CheckParse('a | b union c', '(| (| child::{}a child::{}b) child::{}c)');
  CheckParse('a castable as xs:decimal', '(castable child::{}a xs:decimal)');
  CheckParse('a cast as xs:date?', '(cast child::{}a xs:date?)');
  CheckParse('1.5', '1.5d');
  CheckParse('.5', '0.5d');
  CheckParse('1e3', '1000e');
  CheckParse('''it''''s''', '"it''s"');
  CheckParse('"a""b"', '"a"b"');
  CheckParse('()', '()');
  CheckParse('1 (: a (: nested :) comment :) + 2', '(+ 1 2)');
end;

procedure TestExpressions;
begin
  SetUpContext;
  CheckParse('if (a) then 1 else 2', '(if child::{}a 1 2)');
  CheckParse('for $x in a, $y in $x return $y', '(for child::{}a $2 $3) $2 $3');
  CheckParse('some $x in a satisfies $x = 1', '(some child::{}a (=eq $2 1)) $2');
  CheckParse('every $x in (1, 2) satisfies $x', '(every (seq 1 2) $2) $2');
  CheckParse('not(a)', '(not child::{}a)');
  CheckParse('fn:count(a)', '(count child::{}a)');
  CheckParse('xs:decimal(a)', '(xs:decimal child::{}a)');
  CheckParse('concat(a, b, c, d)', '(concat child::{}a child::{}b child::{}c child::{}d)');
  CheckParse('u:slack(a, 1, 0.02)', '(user0 child::{}a 1 0.02d)');
  CheckParse('current()', '(current)');
end;

procedure TestErrors;
begin
  SetUpContext;
  CheckError('a +', 'XPST0003');
  CheckError('(a', 'XPST0003');
  CheckError('a instance of xs:integer', 'XPST0003');
  CheckError('namespace::a', 'XPST0003');
  CheckError('namespace::a', 'XPST0003');
  CheckError('element(a)', 'XPST0003');
  CheckError('''abc', 'XPST0003');
  CheckError('1a', 'XPST0003');
  CheckError('$undeclared', 'XPST0008');
  CheckError('unknown(1)', 'XPST0017');
  CheckError('count(1, 2)', 'XPST0017');
  CheckError('u:slack(1)', 'XPST0017');
  CheckError('p:a', 'XPST0081');
  CheckError('a cast as xs:duration', 'XPST0051');
  CheckError('a cast as cbc:x', 'XPST0051');
  CheckError('a cast as xs:anyAtomicType', 'XPST0080');
  CheckError('a cast as xs:NOTATION', 'XPST0080');
  CheckError('processing-instruction(cbc:x)', 'XPST0003');
  CheckError('document-node(element(a))', 'XPST0003');
end;

procedure TestSlots;
var
  E: TLandrixXmlXPathExpression;
begin
  SetUpContext;
  E := TLandrixXmlXPathExpression.Create(U('for $a in 1 return for $b in 2 return $a + $b'), Context);
  try
    CheckEquals(4, E.SlotCount, 'two context variables and two locals');
  finally
    E.Free;
  end;
  E := TLandrixXmlXPathExpression.Create(U('1'), nil);
  try
    CheckEquals(0, E.SlotCount, 'no context');
  finally
    E.Free;
  end;
  { a single step is not wrapped in a path node }
  E := TLandrixXmlXPathExpression.Create(U('a[1]'), nil);
  try
    CheckEquals(2, E.NodeCount, 'the step and its predicate only');
  finally
    E.Free;
  end;
  E := TLandrixXmlXPathExpression.Create(U('xs:date(a)'), nil);
  try
    CheckEquals(Ord(xikDate), Ord(E.Nodes[E.Root].AtomicType), 'constructor function with its type');
  finally
    E.Free;
  end;
end;

procedure TearDown;
begin
  Context.Free;
  Context := nil;
end;

procedure TestAll;
begin
  try
    TestPaths;
    TestOperators;
    TestExpressions;
    TestErrors;
    TestSlots;
  finally
    TearDown;
  end;
end;

procedure Register;
begin
  RegisterTest('XPath.Parser', TestAll);
end;

end.
