<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- ISO-8859-1: up to U+00FF as bytes, the rest as character references -->
<xsl:output encoding="ISO-8859-1" indent="yes"/>
<xsl:template match="/"><r a="&#xE9;&#x20AC;&#x1F600;&#xA0;&#x9;x">&#xE9;&#x20AC;&#x1F600;&#xA0;&#x85;&lt;&amp;<xsl:comment>c</xsl:comment><e>&#xFF;</e><xsl:processing-instruction name="p">q</xsl:processing-instruction></r></xsl:template>
</xsl:stylesheet>
