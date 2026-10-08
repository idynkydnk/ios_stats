import SwiftUI
import UIKit

/// Restyles the published HTML without losing illustrations, animations, or tables.
enum SiteRecapReaderStyle {
    static func script(appearance: SiteAppearance, readingSize: Double) -> String {
        let light = appearance.mode == .light
        let text = light ? "#172033" : "#e4e8eb"
        let muted = light ? "#596579" : "#9ba7b6"
        let line = light ? "rgba(23,32,51,.10)" : "rgba(255,255,255,.10)"
        let css = """
        .recap-share-bar,.recap-menu-fab { display:none!important; }
        html.stats-app-reader {
          color-scheme: \(light ? "light" : "dark");
          --recap-bg: \(cssColor(appearance.background));
          --recap-panel: \(cssColor(appearance.panel));
          --recap-text: \(text); --recap-muted: \(muted);
          --recap-accent: \(cssColor(appearance.accent)); --recap-line: \(line);
          --sr-bg: var(--recap-bg); --sr-panel: var(--recap-panel);
          --sr-text: var(--recap-text); --sr-muted: var(--recap-muted);
          --sr-accent: var(--recap-accent); --sr-line: var(--recap-line);
          -webkit-text-size-adjust: 100%;
        }
        .stats-app-reader body,.stats-app-reader .recap-body {
          background:var(--recap-bg)!important; color:var(--recap-text)!important;
          font-family:-apple-system,BlinkMacSystemFont,sans-serif!important;
          font-size:\(readingSize)px; line-height:1.6;
        }
        .stats-app-reader .recap-page { padding:20px 0 32px; }
        .stats-app-reader .recap-page > section[aria-labelledby="recap-subscription-heading"],
        .stats-app-reader .recap-page > p:last-child { display:none; }
        .stats-app-reader .recap-body > :not(.hero-image-card) {
          width:calc(100% - 36px); max-width:680px;
        }
        .stats-app-reader .recap-body h1 {
          color:var(--recap-text)!important; text-align:left; font-weight:750;
          font-size:\(readingSize * 1.65)px; line-height:1.18; letter-spacing:-.6px;
          margin:4px auto 24px; overflow-wrap:anywhere;
        }
        .stats-app-reader .recap-body .hero-image-card {
          width:calc(100% - 24px); max-width:704px; margin:0 auto 24px;
          overflow:hidden; border-radius:\(appearance.style.radius(18))px;
        }
        .stats-app-reader .recap-body .hero-image-card img,
        .stats-app-reader .recap-body video { display:block; width:100%; height:auto; }
        .stats-app-reader .recap-body .card:not(.hero-image-card) {
          background:var(--recap-panel); color:var(--recap-text);
          padding:18px; border:1px solid var(--recap-line);
          border-radius:\(appearance.style.radius(16))px; margin-bottom:18px;
        }
        .stats-app-reader .recap-body .card h2 {
          color:var(--recap-accent); font-size:\(readingSize * 0.82)px;
          letter-spacing:.6px; border-color:var(--recap-line);
        }
        .stats-app-reader .recap-body .summary-text {
          background:transparent; border:0; padding:0;
          font-size:\(readingSize)px; line-height:1.75; color:var(--recap-text);
          overflow-wrap:anywhere;
        }
        .stats-app-reader .recap-body .summary-text p { margin:0 0 1em; }
        .stats-app-reader .recap-body table { color:var(--recap-text); }
        .stats-app-reader .recap-body th,.stats-app-reader .recap-body .time-cell {
          color:var(--recap-muted);
        }
        .stats-app-reader .recap-body td { border-color:var(--recap-line); }
        .stats-app-reader .recap-body .stats-rank { color:var(--recap-accent); }
        .stats-app-reader .recap-body .winner-team,
        .stats-app-reader .recap-body .diff-positive { color:\(light ? "#18703c" : "#4ade80"); }
        .stats-app-reader .recap-body .loser-team,
        .stats-app-reader .recap-body .diff-negative { color:\(light ? "#b42332" : "#f87171"); }
        .stats-app-reader .recap-body .footer { border-color:var(--recap-line); }
        .stats-app-reader .recap-body .link-button {
          background:var(--recap-accent); color:\(light ? "white" : "#0b0f14");
        }
        """
        // JSON encoding keeps the stylesheet a safe JavaScript string literal.
        let encoded = String(data: try! JSONEncoder().encode(css), encoding: .utf8)!
        return """
        (function() {
          if (!document.querySelector('.recap-body')) return;
          document.documentElement.classList.add('stats-app-reader');
          var style = document.getElementById('stats-app-embed');
          if (!style) {
            style = document.createElement('style');
            style.id = 'stats-app-embed';
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = \(encoded);
        })();
        """
    }

    private static func cssColor(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return "rgb(\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255)))"
    }
}
