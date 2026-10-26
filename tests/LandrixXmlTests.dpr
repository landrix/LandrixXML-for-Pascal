{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Console test runner. Exit code 0 = all tests passed.

  Usage: LandrixXmlTests [repository-root] [-filter=Prefix] }

program LandrixXmlTests;

{$I LandrixXml.inc}

{$IFDEF MSWINDOWS}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF FPC}
  {$IFDEF UNIX}
  { threads for Schematron.Threads }
  cthreads,
  {$ENDIF}
  {$ENDIF}
  SysUtils,
  LandrixXmlTestFramework,
  LandrixXmlTestSelf,
  LandrixXmlTestBase,
  LandrixXmlTestEncoding,
  LandrixXmlTestReader,
  LandrixXmlTestReaderErrors,
  LandrixXmlTestWriter,
  LandrixXmlTestConvert,
  LandrixXmlTestDom,
  LandrixXmlTestDecimal,
  LandrixXmlTestDouble,
  LandrixXmlTestRegex,
  LandrixXmlTestNormalize,
  LandrixXmlTestXsdTypes,
  LandrixXmlTestXsdContent,
  LandrixXmlTestXsdValidator,
  LandrixXmlTestXPathTree,
  LandrixXmlTestXPath,
  LandrixXmlTestXPathEval,
  LandrixXmlTestSha256,
  LandrixXmlTestSchematron,
  LandrixXmlTestLocal;

function FilterParam: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount do
    if Copy(ParamStr(I), 1, 8) = '-filter=' then
      Result := Copy(ParamStr(I), 9, MaxInt);
end;

begin
  LandrixXmlTestSelf.Register;
  LandrixXmlTestBase.Register;
  LandrixXmlTestEncoding.Register;
  LandrixXmlTestReader.Register;
  LandrixXmlTestReaderErrors.Register;
  LandrixXmlTestWriter.Register;
  LandrixXmlTestConvert.Register;
  LandrixXmlTestDom.Register;
  LandrixXmlTestDecimal.Register;
  LandrixXmlTestDouble.Register;
  LandrixXmlTestRegex.Register;
  LandrixXmlTestNormalize.Register;
  LandrixXmlTestXsdTypes.Register;
  LandrixXmlTestXsdContent.Register;
  LandrixXmlTestXsdValidator.Register;
  LandrixXmlTestXPathTree.Register;
  LandrixXmlTestXPath.Register;
  LandrixXmlTestXPathEval.Register;
  LandrixXmlTestSha256.Register;
  LandrixXmlTestSchematron.Register;
  LandrixXmlTestLocal.Register;
  ExitCode := RunAllTests(FilterParam);
end.
