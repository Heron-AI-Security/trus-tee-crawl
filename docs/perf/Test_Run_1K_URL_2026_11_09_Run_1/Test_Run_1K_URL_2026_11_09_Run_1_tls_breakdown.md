# TLS breakdown of the run `Test_Run_1K_URL_2026_11_09_Run_1`

Every outcome of every round is in exactly one case, so the cases add up to the total (908 outcomes). Made by `ops/perf/run_tls_breakdown.py` from the signed outcome records and the receipts.

## 1. All outcomes

| Case | Group | Count | Share of all outcomes |
|---|---|---|---|
| A. TLS authenticated (valid chain, hostname matches, dates enclose the fetch) | HTTPS page with a receipt | 653 | 71.9 % |
| B1. not authenticated: chain expired | HTTPS page with a receipt | 9 | 1.0 % |
| B2. not authenticated: chain expired and hostname mismatch | HTTPS page with a receipt | 1 | 0.1 % |
| B3. not authenticated: hostname not in the certificate (chain valid) | HTTPS page with a receipt | 2 | 0.2 % |
| B4. not authenticated: chain from an untrusted issuer | HTTPS page with a receipt | 1 | 0.1 % |
| C. plain HTTP URL: no TLS at all | Plain HTTP | 127 | 14.0 % |
| D. HTTPS: the TLS handshake failed | TLS failed | 2 | 0.2 % |
| E1. HTTPS: no connection (DNS failure, timeout, refused) | No TLS evidence recorded | 20 | 2.2 % |
| E2. HTTPS: the server answered with an error status (page not stored) | No TLS evidence recorded | 35 | 3.9 % |
| E4. HTTPS: page not found (404 or 410) | No TLS evidence recorded | 16 | 1.8 % |
| E5. HTTPS: redirect or another status (page not stored) | No TLS evidence recorded | 16 | 1.8 % |
| E6. HTTPS: page truncated at the content limit (no receipt) | No TLS evidence recorded | 23 | 2.5 % |
| E7. HTTPS: not attempted (dropped at the task timeout) | No TLS evidence recorded | 3 | 0.3 % |
| **Total** | | **908** | 100.0 % |

By group: HTTPS page with a receipt 666 (73.3 %); Plain HTTP 127 (14.0 %); TLS failed 2 (0.2 %); No TLS evidence recorded 113 (12.4 %).

## 2. HTTPS pages with a receipt (666)

| Case | Count | Share of the pages with a receipt |
|---|---|---|
| A. TLS authenticated (valid chain, hostname matches, dates enclose the fetch) | 653 | 98.0 % |
| B1. not authenticated: chain expired | 9 | 1.4 % |
| B2. not authenticated: chain expired and hostname mismatch | 1 | 0.2 % |
| B3. not authenticated: hostname not in the certificate (chain valid) | 2 | 0.3 % |
| B4. not authenticated: chain from an untrusted issuer | 1 | 0.2 % |

TLS protocol versions of those pages: TLSv1.3 613, TLSv1.2 53.

Cipher suites: TLS_AES_128_GCM_SHA256 454, TLS_AES_256_GCM_SHA384 158, TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 24, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 19, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 3, TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 2, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA 2, TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 2, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA 1, TLS_CHACHA20_POLY1305_SHA256 1.

## 3. The sources that were not authenticated

| Case | Host |
|---|---|
| B1 | ayudiapopysesilia.blog.uma.ac.id |
| B1 | dadanramdan64.blog.uma.ac.id |
| B1 | fernelmont.energieleveranciersbelgie.be |
| B1 | graceyuswita.blog.uma.ac.id |
| B1 | peakvalleyrisk.com |
| B1 | www.ekstromcatering.fi |
| B1 | www.mickaloha.com |
| B1 | www.orangeseal.us |
| B1 | www.sicurellafotografi.it |
| B2 | ftp.rfvoip.com |
| B3 | judyconrad.ca |
| B3 | marie-clareboothman.com |
| B4 | yrpnd.mzsakha.ru |

## 4. Examples of the other cases (up to 5 hosts each)

| Case | Hosts |
|---|---|
| C | 111amyh.com, 3k74.com, 4301119.com, 51bzds.com, acmepower.ru |
| D | heraldbangla.com, mickaelpreti.com |
| E1 | data.lekbeshimun.gov.np, epicred.in, f7ab.com, frozensoftware.com, housepainter-simsburyct.com |
| E2 | acapulcolwr.com, ausserrandundband.com, avologytechnologies.com, avolonaccounting.com, baliluxuryestate.com |
| E4 | amazingpakistanis.com, blackwingzlimo.com, fa.hiconpopdisplays.com, m.inqaahe.com, naturallyinformed.net |
| E5 | akazawaroseki.com, autoskolatigeris.lv, blun.ai, handonheartwine.com, hellojessika.com |
| E6 | alejandraguerrero.xyz, bestlistbd.com, dkestilistas.com, grandeloge.nl, motowilder.in |
| E7 | arcadia-intellicad.pl, cateringsanchez.com, pleubian.over-blog.com |

## 5. How the cases are decided

1. A URL that is not `https` is case C, whatever happened to it afterwards. 2. An `ACCEPTED` outcome has a receipt: authenticated (A), or not authenticated for the reason that the receipt's own validation facts give (B1 to B6). 3. An SSL, TLS, handshake or certificate error in the report of a failed fetch is case D. 4. All other outcomes stored no page, so no TLS evidence was recorded: no connection (E1), an error status (E2), robots.txt (E3), not found (E4), a redirect or another status (E5), a truncated page (E6), not attempted (E7), or another failure (E8). A receipt exists only for an ACCEPTED page; an HTTPS fetch that ended in an error status or a redirect did complete a handshake, but the crawler did not record its certificate, so it is E and not A or B.
