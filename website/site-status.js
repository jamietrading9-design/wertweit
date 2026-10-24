async function refreshWebsiteSettings() {
  const config = window.WERTWEIT_SUPABASE;
  if (!config?.url || !config?.publishableKey) {
    console.error("Website status is unavailable because the public Supabase configuration is missing.");
    return;
  }

  try {
    const endpoint = new URL("/rest/v1/app_settings", config.url);
    endpoint.search = new URLSearchParams({
      select: "website_maintenance_enabled,website_maintenance_message,website_announcement_enabled,website_announcement_title,website_announcement_message",
      id: "eq.1",
      limit: "1",
    }).toString();
    const response = await fetch(endpoint, {
      headers: { apikey: config.publishableKey },
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`Supabase returned HTTP ${response.status}`);
    const rows = await response.json();
    if (!Array.isArray(rows) || !rows[0]) throw new Error("Website status settings were not found.");

    const settings = rows[0];
    const maintenance = settings.website_maintenance_enabled === true;
    const maintenanceMessage = document.querySelector("#site-maintenance-message");
    const maintenancePage = document.querySelector("#site-maintenance");
    if (!maintenanceMessage || !maintenancePage) {
      throw new Error("The website maintenance view is missing from this page.");
    }
    maintenanceMessage.textContent = settings.website_maintenance_message;
    maintenancePage.hidden = !maintenance;
    document.querySelectorAll(".site-header, main, footer").forEach((element) => {
      element.hidden = maintenance;
    });

    const announcement = settings.website_announcement_enabled === true &&
      settings.website_announcement_title && settings.website_announcement_message;
    const announcementTitle = document.querySelector("#site-announcement-title");
    const announcementMessage = document.querySelector("#site-announcement-message");
    const announcementBanner = document.querySelector("#site-announcement");
    if (!announcementTitle || !announcementMessage || !announcementBanner) {
      throw new Error("The website announcement view is missing from this page.");
    }
    announcementTitle.textContent = announcement ? settings.website_announcement_title : "";
    announcementMessage.textContent = announcement ? settings.website_announcement_message : "";
    announcementBanner.hidden = !announcement || maintenance;
  } catch (error) {
    console.error("Could not refresh public website settings.", error);
  }
}

refreshWebsiteSettings();
window.setInterval(refreshWebsiteSettings, 60_000);
