import Foundation
import CryptoKit

public struct ClaudeOrganization: Decodable, Equatable {
    public let uuid: String
    public let name: String
}

/// Only quota data crosses the WebKit boundary; session cookies stay in WebKit.
public struct ClaudeWebReply: Decodable {
    public let status: Int
    public let organizations: [ClaudeOrganization]?
    public let organization: String?
    public let usage: ClaudeUsageResponse?
    public let retryAfter: Double?

    public func snapshot(now: Date = Date()) throws -> UsageSnapshot {
        switch status {
        case 200: break
        case 401: throw ClaudeUsageError.notSignedIn
        case 403: throw ClaudeUsageError.scopeMissing
        case 409: throw ClaudeUsageError.ambiguousAccount
        case 429: throw ClaudeUsageError.throttled(max(300, min(3600, retryAfter ?? 600)))
        default: throw ClaudeUsageError.network
        }
        guard let organization, UUID(uuidString: organization) != nil,
              organizations?.contains(where: { $0.uuid.lowercased() == organization.lowercased() }) == true,
              let usage else { throw ClaudeUsageError.invalidResponse }
        let response = usage.normalized
        guard !response.windows.isEmpty else { throw ClaudeUsageError.unavailable }
        // A web subscription is scoped to an organization. A separate namespace
        // intentionally starts a fresh baseline when migrating from desktop OAuth.
        let identity = "claude-web/" + organization.lowercased()
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return UsageSnapshot(response: response, accountKey: hash, fetchedAt: now)
    }
}

public enum ClaudeWebAPI {
    public static func isClaudeOrigin(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host?.lowercased() == "claude.ai" && (url?.port == nil || url?.port == 443)
    }

    // Runs in an isolated content world on claude.ai, using that page's own
    // session. Never reads cookies, passwords, messages, or a desktop keychain.
    // `selectedOrganization` is a callAsyncJavaScript argument, not interpolated code.
    public static let script = #"""
    if (location.origin !== 'https://claude.ai') return JSON.stringify({status:401});
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    const get = async path => {
        const r = await fetch(path, {method:'GET', credentials:'same-origin',
            cache:'no-store', redirect:'error', headers:{Accept:'application/json'}, signal:controller.signal});
        if (!r.ok) return {status:r.status, retryAfter:Number(r.headers.get('Retry-After')) || 600};
        if (!(r.headers.get('Content-Type') || '').includes('application/json')) return {status:401};
        const text = await r.text();
        if (text.length > 1000000) return {status:502};
        return {status:200, data:JSON.parse(text)};
    };
    try {
        const result = await get('/api/organizations');
        if (result.status !== 200) return JSON.stringify(result);
        if (!Array.isArray(result.data)) return JSON.stringify({status:502});
        const organizations = result.data.filter(o => typeof o.uuid === 'string' &&
            /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(o.uuid))
            .map(o => ({uuid:o.uuid, name:typeof o.name === 'string' ? o.name.slice(0,120) : 'Claude'}));
        const selected = organizations.find(o => o.uuid === selectedOrganization);
        // Never silently switch to a different organization when a saved choice disappears.
        const org = selected || (!selectedOrganization && organizations.length === 1 ? organizations[0] : null);
        if (!org) return JSON.stringify({status:organizations.length ? 409 : 401, organizations});
        const resultUsage = await get('/api/organizations/' + encodeURIComponent(org.uuid) + '/usage');
        if (resultUsage.status !== 200) return JSON.stringify({status:resultUsage.status, retryAfter:resultUsage.retryAfter, organizations});
        const usage = {};
        for (const key of ['five_hour','seven_day','seven_day_sonnet','seven_day_opus']) {
            const window = resultUsage.data?.[key];
            if (window && typeof window.utilization === 'number' && Number.isFinite(window.utilization)) {
                usage[key] = {utilization:window.utilization, resets_at:typeof window.resets_at === 'string' ? window.resets_at : null};
            }
        }
        // Current Claude usage identifies Fable through a model-scoped weekly
        // limit. Internal bucket codenames are not a stable model identifier.
        const fable = Array.isArray(resultUsage.data?.limits) ? resultUsage.data.limits.filter(row =>
            row?.kind === 'weekly_scoped' && row?.scope?.model?.display_name === 'Fable') : [];
        if (fable.length === 1 && typeof fable[0].percent === 'number' &&
            Number.isFinite(fable[0].percent) && fable[0].percent >= 0) {
            usage.seven_day_fable = {utilization:fable[0].percent,
                resets_at:typeof fable[0].resets_at === 'string' ? fable[0].resets_at : null};
        }
        return JSON.stringify({status:200, organizations, organization:org.uuid, usage});
    } catch { return JSON.stringify({status:503}); }
    finally { clearTimeout(timer); }
    """#
}
