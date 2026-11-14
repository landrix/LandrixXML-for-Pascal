<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- xsl:sort in xsl:for-each: case-order, data-type, empty keys and NaN first, stable, several keys, position(), a sequence constructor -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:variable name="w" select="('b','B','a','A','ab','Ab','aB','c')"/>
plain: <xsl:for-each select="$w"><xsl:sort/><xsl:value-of select="."/>,</xsl:for-each>
upper: <xsl:for-each select="$w"><xsl:sort case-order="upper-first"/><xsl:value-of select="."/>,</xsl:for-each>
late: <xsl:for-each select="('xaB','xAb','xab','xAB')"><xsl:sort case-order="upper-first"/><xsl:value-of select="."/>,</xsl:for-each>
latelow: <xsl:for-each select="('xaB','xAb','xab','xAB')"><xsl:sort case-order="lower-first"/><xsl:value-of select="."/>,</xsl:for-each>
lower: <xsl:for-each select="$w"><xsl:sort case-order="lower-first"/><xsl:value-of select="."/>,</xsl:for-each>
num: <xsl:for-each select="('10','9','x','','-1')"><xsl:sort data-type="number"/><xsl:value-of select="."/>,</xsl:for-each>
numdesc: <xsl:for-each select="('10','9','x','','-1')"><xsl:sort data-type="number" order="descending"/><xsl:value-of select="."/>,</xsl:for-each>
text: <xsl:for-each select="(10, 9, 100)"><xsl:sort data-type="text"/><xsl:value-of select="."/>,</xsl:for-each>
typed: <xsl:for-each select="(10, 9, 100)"><xsl:sort/><xsl:value-of select="."/>,</xsl:for-each>
dates: <xsl:for-each select="(xs:date('2001-01-02'), xs:date('2000-12-31'))"><xsl:sort/><xsl:value-of select="."/>,</xsl:for-each>
empty: <xsl:for-each select="(3,1,2)"><xsl:sort select="if (. = 2) then () else ."/><xsl:value-of select="."/>,</xsl:for-each>
nanempty: <xsl:for-each select="(3, xs:double('NaN'), 1, 2)"><xsl:sort select="if (. = 2) then () else ."/><xsl:value-of select="."/>,</xsl:for-each>
nandesc: <xsl:for-each select="(3, xs:double('NaN'), 1, 2)"><xsl:sort select="if (. = 2) then () else ." order="descending"/><xsl:value-of select="."/>,</xsl:for-each>
stable: <xsl:for-each select="('b1','a1','b2','a2')"><xsl:sort select="substring(.,1,1)" order="descending"/><xsl:value-of select="."/>,</xsl:for-each>
two: <xsl:for-each select="('b1','a1','b2','a2')"><xsl:sort select="substring(.,1,1)"/><xsl:sort select="substring(.,2)" order="descending"/><xsl:value-of select="."/>,</xsl:for-each>
pos: <xsl:for-each select="('x','y','z')"><xsl:sort select="-position()"/><xsl:value-of select="concat(., position(), last())"/>,</xsl:for-each>
body: <xsl:for-each select="('b','a')"><xsl:sort><xsl:value-of select="."/></xsl:sort><xsl:value-of select="."/>,</xsl:for-each>
called: <xsl:for-each select="('b','c','a')"><xsl:sort stable="yes"><xsl:call-template name="key"/></xsl:sort><xsl:value-of select="."/>,</xsl:for-each>
textempty: <xsl:for-each select="(1,2)"><xsl:sort select="if (. = 1) then '' else ()" data-type="text"/><xsl:value-of select="."/>,</xsl:for-each>
coll: <xsl:for-each select="('a','B')"><xsl:sort collation="http://www.w3.org/2005/xpath-functions/collation/codepoint" case-order="upper-first"/><xsl:value-of select="."/>,</xsl:for-each>
kelvin: <xsl:for-each select="('&#x212A;','K','k')"><xsl:sort case-order="lower-first"/><xsl:value-of select="."/>,</xsl:for-each>
pres: <xsl:for-each select="1" xml:space="preserve"> <xsl:value-of select="."/></xsl:for-each>|
pres2: <xsl:for-each select="(2,1)" xml:space="preserve"> <xsl:sort/> <xsl:value-of select="."/></xsl:for-each>|
wsbody: <xsl:for-each select="(2,1)"><xsl:sort xml:space="preserve"> </xsl:sort><xsl:value-of select="."/></xsl:for-each>|
stableavt: <xsl:for-each select="(2,1)"><xsl:sort stable="{'yes'}"/><xsl:value-of select="."/></xsl:for-each>|
avt: <xsl:for-each select="('b','a','c')"><xsl:sort order="{if (1) then 'descending' else 'ascending'}"/><xsl:value-of select="."/>,</xsl:for-each>
<xsl:text>&#10;</xsl:text>
</xsl:template>
<xsl:template name="key"><xsl:value-of select="translate(., 'abc', 'cab')"/></xsl:template>
</xsl:stylesheet>
