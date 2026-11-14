<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- roman numerals above 9999; a grouping size of 0 or less -->
<xsl:template match="/"><r><xsl:number value="9999" format="I"/>|<xsl:number value="10000" format="I"/>|<xsl:number
  value="12345" format="i"/>|<xsl:number value="3000" grouping-size="-1" grouping-separator=","/>|<xsl:number
  value="3000" grouping-size="0" grouping-separator=","/>|<xsl:number value="3000000" grouping-size="3" grouping-separator="."/></r></xsl:template>
</xsl:stylesheet>
