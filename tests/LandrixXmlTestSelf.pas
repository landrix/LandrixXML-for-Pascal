{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Self-tests of the test framework and of compiler assumptions that the
  library relies on. If one of these fails, every other result is suspect. }

unit LandrixXmlTestSelf;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlTestFramework;

procedure TestCheckPasses;
begin
  Check(True, 'Check(True)');
  CheckEquals(1, 1, 'CheckEquals');
  CheckEqualsInt64(5000000000, 5000000000, 'CheckEqualsInt64');
  CheckEqualsStr('abc', 'abc', 'CheckEqualsStr');
  CheckEqualsBytes(Bytes([$C3, $A4]), Bytes([$C3, $A4]), 'CheckEqualsBytes');
  CheckEqualsWide(Wide([$00E4, $20AC]), Wide([$00E4, $20AC]), 'CheckEqualsWide');
end;

procedure TestCheckFails;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    CheckEqualsBytes(Bytes([1, 2]), Bytes([1, 3]), 'deliberate');
  except
    on E: ETestFailure do
    begin
      Raised := True;
      Check(Pos('01 02', E.Message) > 0, 'hex dump of expected value in message');
      Check(Pos('01 03', E.Message) > 0, 'hex dump of actual value in message');
    end;
  end;
  Check(Raised, 'CheckEqualsBytes must fail on different bytes');

  Raised := False;
  try
    CheckEquals(1, 2, 'deliberate');
  except
    on E: ETestFailure do
      Raised := True;
  end;
  Check(Raised, 'CheckEquals must fail on different values');
end;

procedure TestHelpers;
begin
  CheckEquals(0, Length(Bytes([])), 'empty Bytes');
  CheckEqualsStr('00 FF', BytesToHex(Bytes([0, 255])), 'BytesToHex');
  CheckEqualsStr('D83D DE00', WideToHex(Wide([$D83D, $DE00])), 'WideToHex');
end;

procedure TestCompilerAssumptions;
var
  P: PAnsiChar;
  S: AnsiString;
begin
  CheckEquals(1, SizeOf(AnsiChar), 'SizeOf(AnsiChar)');
  CheckEquals(2, SizeOf(WideChar), 'SizeOf(WideChar)');
  CheckEquals(1, SizeOf(Byte), 'SizeOf(Byte)');
  CheckEquals(4, SizeOf(Integer), 'SizeOf(Integer)');
  CheckEquals(4, SizeOf(Cardinal), 'SizeOf(Cardinal)');
  CheckEquals(8, SizeOf(Int64), 'SizeOf(Int64)');
  CheckEquals(SizeOf(Pointer), SizeOf(PAnsiChar), 'SizeOf(PAnsiChar)');
{$IFDEF LANDRIXXML_UNICODE}
  CheckEquals(2, SizeOf(Char), 'SizeOf(Char) on Unicode Delphi');
{$ELSE}
  CheckEquals(1, SizeOf(Char), 'SizeOf(Char) on Ansi compilers');
{$ENDIF}
  { byte access through PAnsiChar must not depend on the code page }
  S := Bytes([$E2, $82, $AC]);
  P := PAnsiChar(S);
  CheckEquals($E2, Ord(P[0]), 'PAnsiChar[0]');
  CheckEquals($AC, Ord(P[2]), 'PAnsiChar[2]');
  CheckEquals(0, Ord(P[3]), 'AnsiString is zero-terminated');
end;

procedure Register;
begin
  RegisterTest('Self.CheckPasses', TestCheckPasses);
  RegisterTest('Self.CheckFails', TestCheckFails);
  RegisterTest('Self.Helpers', TestHelpers);
  RegisterTest('Self.CompilerAssumptions', TestCompilerAssumptions);
end;

end.
