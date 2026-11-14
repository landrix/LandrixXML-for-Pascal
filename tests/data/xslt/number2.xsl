<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a format without tokens, the largest value, the default format -->
<xsl:template match="/">
  <r><a><xsl:number value="(1, 2, 3)" format="---"/></a><b><xsl:number value="2147483647"/></b>
  <c><xsl:number value="0"/></c><d><xsl:number value="(1, 2)" format="(1)"/></d></r>
</xsl:template>
</xsl:stylesheet>
