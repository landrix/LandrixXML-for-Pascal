<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- a parameter of xsl:iterate without a value its type allows -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:param name="p" as="xs:integer"/><xsl:value-of select="."/></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
