<?xml version="1.0" encoding="UTF-8"?>
<!-- exclude-result-prefixes names namespace URIs where it is: a prefix
     bound to another URI further in is copied (and a namespace node
     binding that prefix otherwise is XTDE0430, see
     err-namespace-exclude), #all and #default exclude the URIs in scope
     there, another prefix for an excluded URI is excluded too. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:old" xmlns:q="urn:old" xmlns="urn:d" exclude-result-prefixes="p #default">
  <xsl:template match="/">
    <out xmlns="">
      <a xmlns:p="urn:new"/>
      <b xmlns:q="urn:q" xsl:exclude-result-prefixes="#all"><c/></b>
      <d xmlns="urn:d"/>
      <e xmlns="urn:e"/>
    </out>
  </xsl:template>
</xsl:stylesheet>
