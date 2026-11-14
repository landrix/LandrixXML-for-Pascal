<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- unparsed-text-available() with an encoding that is not supported -->
<xsl:output method="text"/>
<xsl:template match="/"><xsl:value-of select="unparsed-text-available('_text.txt', 'bogus')"/></xsl:template>
</xsl:stylesheet>
