<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:my="urn:my" xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:fn="http://www.w3.org/2005/xpath-functions" xmlns:i="urn:landrix:xslt-internal">
<!-- function-available(), element-available(), system-property(): names
     resolved with the namespaces of the expression, white space around
     them allowed -->
<xsl:function name="my:f"><xsl:param name="a"/><xsl:sequence select="1"/></xsl:function>
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of separator="|" select="function-available('concat'), function-available('concat', 5),
  function-available('true', 1), function-available(' fn:key ', 2), function-available('key', 4),
  function-available('xs:integer'), function-available('xs:integer', 2), function-available('my:f'),
  function-available('my:f', 1), function-available('my:f', 2), function-available('my:f', -1),
  function-available('current-group', 0), function-available('format-number', 3),
  function-available('unparsed-text-available', 2), function-available('my:g'), function-available('i:global', 1),
  element-available('xsl:for-each'), element-available('xsl:template'), element-available('for-each'),
  element-available('xsl:fallback'), element-available('xsl:foo'), element-available('my:x'),
  element-available('xsl:for-each-group'),
  system-property('version'), system-property('xsl:is-schema-aware'),
  system-property('xsl:supports-serialization'), system-property('xsl:foo')"/>
</xsl:template>
</xsl:stylesheet>
