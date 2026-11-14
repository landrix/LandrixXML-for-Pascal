<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xsl:template match="/"><out><xsl:value-of select="xs:integer('x')"/></out></xsl:template>
</xsl:stylesheet>
