#!/usr/bin/env python3
"""
cve_lookup.py - Busca CVEs no NVD (API 2.0) a partir de produto/versão
ou direto do XML do nmap (-oX / -oA). Só stdlib, roda em qualquer Kali.

Uso:
  python3 cve_lookup.py "vsftpd 2.3.4"
  python3 cve_lookup.py "Apache httpd 2.4.49" --max 10
  python3 cve_lookup.py --nmap 02_detail.xml
  python3 cve_lookup.py "webmin 1.910" --exploit        # + searchsploit
  NVD_API_KEY=xxxx python3 cve_lookup.py ...            # rate limit maior

Sem chave: NVD permite ~5 requisições / 30s (o script espera sozinho).
"""
import argparse, json, os, shutil, subprocess, sys, time
import urllib.parse, urllib.request
import xml.etree.ElementTree as ET

NVD = "https://services.nvd.nist.gov/rest/json/cves/2.0"
C = {"r": "\033[1;31m", "y": "\033[1;33m", "g": "\033[1;32m", "b": "\033[1;34m", "n": "\033[0m"}


def sev_color(score):
    if score is None:
        return C["n"]
    return C["r"] if score >= 9 else C["y"] if score >= 7 else C["g"]


def nvd_search(keyword, max_results=8):
    params = {"keywordSearch": keyword, "resultsPerPage": 50}
    url = NVD + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "cve-lookup-ctf"})
    key = os.environ.get("NVD_API_KEY")
    if key:
        req.add_header("apiKey", key)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.load(r)
    except Exception as e:  # sem internet / rate limit
        print(f"  {C['y']}[!] NVD indisponível ({e}). Use searchsploit offline.{C['n']}")
        return []
    out = []
    for item in data.get("vulnerabilities", []):
        cve = item["cve"]
        m = cve.get("metrics", {})
        score, vector = None, ""
        for k in ("cvssMetricV31", "cvssMetricV30", "cvssMetricV2"):
            if m.get(k):
                d = m[k][0]["cvssData"]
                score, vector = d.get("baseScore"), d.get("vectorString", "")
                break
        desc = next((d["value"] for d in cve.get("descriptions", []) if d["lang"] == "en"), "")
        kev = "cisaExploitAdd" in cve  # está no catálogo KEV = explorado de verdade
        out.append({"id": cve["id"], "score": score, "vector": vector, "desc": desc, "kev": kev})
    # ordena: KEV primeiro, depois maior CVSS
    out.sort(key=lambda x: (x["kev"], x["score"] or 0), reverse=True)
    return out[:max_results]


def searchsploit(term):
    if not shutil.which("searchsploit"):
        print(f"  {C['y']}[!] searchsploit não instalado{C['n']}")
        return
    res = subprocess.run(["searchsploit", "--disable-colour", term], capture_output=True, text=True)
    lines = [l for l in res.stdout.splitlines() if "|" in l and "Exploit Title" not in l]
    if lines:
        print(f"  {C['b']}Exploit-DB:{C['n']}")
        for l in lines[:10]:
            print("    " + l.strip())
    else:
        print("  Exploit-DB: nada para esse termo (tente encurtar a versão)")


# nomes que o nmap reporta diferente do NVD
ALIASES = {
    "MiniServ": "Webmin", "Apache httpd": "Apache HTTP Server", "Microsoft IIS httpd": "Microsoft IIS",
    "OpenSSH": "OpenSSH", "ProFTPD": "ProFTPD", "Apache Tomcat": "Apache Tomcat",
    "nginx": "nginx", "Samba smbd": "Samba", "MySQL": "MySQL", "Werkzeug httpd": "Werkzeug",
}


def from_nmap(xml_path):
    """Extrai 'produto versão' de cada porta do XML do nmap."""
    terms = []
    root = ET.parse(xml_path).getroot()
    for port in root.iter("port"):
        st = port.find("state")
        svc = port.find("service")
        if st is None or st.get("state") != "open" or svc is None:
            continue
        prod, ver = svc.get("product", ""), svc.get("version", "")
        if prod and ver:
            # pega só major.minor[.patch] - NVD casa melhor
            ver = ver.split()[0]
            prod = ALIASES.get(prod, prod)
            terms.append((port.get("portid"), f"{prod} {ver}"))
    return terms


def show(term, max_results, exploit):
    print(f"\n{C['b']}[*] {term}{C['n']}")
    for v in nvd_search(term, max_results):
        col = sev_color(v["score"])
        kev = f" {C['r']}[KEV - explorado ativamente]{C['n']}" if v["kev"] else ""
        print(f"  {col}{v['id']:<16} CVSS {v['score']}{C['n']}{kev}")
        print(f"      {v['desc'][:180]}")
    if exploit:
        searchsploit(term)


def main():
    ap = argparse.ArgumentParser(description="CVE lookup (NVD + searchsploit)")
    ap.add_argument("term", nargs="?", help='ex: "OpenSSH 7.2p2"')
    ap.add_argument("--nmap", help="XML do nmap (-oX/-oA)")
    ap.add_argument("--max", type=int, default=8)
    ap.add_argument("--exploit", action="store_true", help="também roda searchsploit")
    a = ap.parse_args()
    if not a.term and not a.nmap:
        ap.print_help(); sys.exit(1)
    jobs = [(None, a.term)] if a.term else from_nmap(a.nmap)
    if a.nmap and not jobs:
        print("Nenhum serviço com produto+versão no XML (rodou com -sV?)")
    for i, (port, term) in enumerate(jobs):
        if port:
            print(f"\n{C['g']}=== porta {port} ==={C['n']}", end="")
        show(term, a.max, a.exploit or bool(a.nmap))
        if i < len(jobs) - 1 and not os.environ.get("NVD_API_KEY"):
            time.sleep(6.5)  # respeita rate limit público


if __name__ == "__main__":
    main()
