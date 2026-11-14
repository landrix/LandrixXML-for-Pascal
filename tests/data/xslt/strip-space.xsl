<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:p="urn:p" exclude-result-prefixes="p">
<!-- xsl:strip-space and xsl:preserve-space: "*", "prefix:*" and names, priorities, the import precedence, xml:space, documents read by doc() -->
<xsl:import href="_strip-space-imported.xsl"/>
<xsl:strip-space elements="*"/>
<xsl:preserve-space elements="keep p:*"/>
<xsl:strip-space elements="p:gone"/>
<xsl:preserve-space elements="*:star"/>
<xsl:output method="xml"/>
<xsl:template match="/">
<r>
<xsl:for-each select="//*[not(self::doc)]"><e n="{name()}" c="{count(text())}" s="{string-join(text(), '|')}"/></xsl:for-each>
<xsl:for-each select="doc('_strip-space-doc.xml')//x"><d c="{count(text())}"/></xsl:for-each>
</r>
</xsl:template>
</xsl:stylesheet>
