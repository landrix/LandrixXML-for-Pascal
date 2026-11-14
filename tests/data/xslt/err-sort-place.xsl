<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- xsl:sort after other content -->
<xsl:template match="/"><r><xsl:for-each select="(1,2)"><x/><xsl:sort/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
