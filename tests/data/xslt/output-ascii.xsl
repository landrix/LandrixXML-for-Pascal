<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- characters US-ASCII does not have: character references in text and attributes -->
<xsl:output encoding="us-ascii"/>
<xsl:template match="/"><r a="&#xE9;&#x20AC;&#x1F600;&#xA0;&#x9;x">&#xE9;&#x20AC;&#x1F600;&#xA0;&#x85;&lt;&amp;<xsl:comment>c</xsl:comment><e>&#xFF;</e><xsl:processing-instruction name="p">q</xsl:processing-instruction></r></xsl:template>
</xsl:stylesheet>
