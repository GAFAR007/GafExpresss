/**
 * apps/backend/services/address_autocomplete.service.js
 * -----------------------------------------------------
 * WHAT:
 * - Provides address autocomplete + place details via Google Places API.
 *
 * WHY:
 * - Frontend needs suggestions to auto-fill structured addresses.
 * - Keeps API keys server-side (safer for production).
 *
 * HOW:
 * - Calls Places Autocomplete for suggestions (country: NG, address type).
 * - Calls Place Details to map components into our address shape.
 * - Returns normalized fields for frontend controllers.
 */

const https = require('https');
const { URL } = require('url');
const debug = require('../utils/debug');

const GOOGLE_PLACES_API_KEY =
  process.env.GOOGLE_PLACES_API_KEY || process.env.GOOGLE_ADDRESS_API_KEY;

const AUTOCOMPLETE_ENDPOINT =
  'https://maps.googleapis.com/maps/api/place/autocomplete/json';
const PLACE_DETAILS_ENDPOINT =
  'https://maps.googleapis.com/maps/api/place/details/json';

function assertApiKey() {
  if (!GOOGLE_PLACES_API_KEY) {
    throw new Error('Google Places API key is not configured');
  }
}

function getJson(urlString) {
  const url = new URL(urlString);

  return new Promise((resolve, reject) => {
    const request = https.request(
      {
        method: 'GET',
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        port: 443,
        timeout: 10000,
      },
      (response) => {
        let data = '';
        response.on('data', (chunk) => {
          data += chunk;
        });
        response.on('end', () => {
          try {
            const parsed = JSON.parse(data);
            resolve({ status: response.statusCode || 0, data: parsed });
          } catch (err) {
            resolve({ status: response.statusCode || 0, data: data || null });
          }
        });
      }
    );

    request.on('error', reject);
    request.on('timeout', () => {
      request.destroy(new Error('Request timeout'));
    });
    request.end();
  });
}

function findComponent(components, type) {
  return components.find((component) => component.types?.includes(type));
}

function normalizeComponentValue(components, type) {
  const component = findComponent(components, type);
  return component?.long_name || component?.short_name || null;
}

async function fetchAddressSuggestions(query) {
  assertApiKey();

  const cleaned = (query || '').trim();
  if (!cleaned) {
    throw new Error('Query is required');
  }

  const url = new URL(AUTOCOMPLETE_ENDPOINT);
  url.searchParams.set('input', cleaned);
  url.searchParams.set('key', GOOGLE_PLACES_API_KEY);
  url.searchParams.set('components', 'country:ng');
  url.searchParams.set('types', 'address');

  debug('ADDRESS AUTOCOMPLETE: request', { length: cleaned.length });

  const { status, data } = await getJson(url.toString());
  if (status < 200 || status >= 300) {
    debug('ADDRESS AUTOCOMPLETE: HTTP error', { status });
    throw new Error('Address autocomplete failed');
  }

  if (!data || data.status !== 'OK') {
    debug('ADDRESS AUTOCOMPLETE: Google status', {
      status: data?.status,
      error: data?.error_message,
    });
    throw new Error('Address autocomplete failed');
  }

  const suggestions = (data.predictions || []).map((item) => ({
    placeId: item.place_id,
    description: item.description,
    mainText: item.structured_formatting?.main_text || '',
    secondaryText: item.structured_formatting?.secondary_text || '',
  }));

  debug('ADDRESS AUTOCOMPLETE: success', {
    count: suggestions.length,
  });

  return suggestions;
}

async function fetchPlaceDetails(placeId) {
  assertApiKey();

  const cleaned = (placeId || '').trim();
  if (!cleaned) {
    throw new Error('placeId is required');
  }

  const url = new URL(PLACE_DETAILS_ENDPOINT);
  url.searchParams.set('place_id', cleaned);
  url.searchParams.set('key', GOOGLE_PLACES_API_KEY);
  url.searchParams.set(
    'fields',
    'address_component,formatted_address,geometry'
  );

  debug('ADDRESS PLACE DETAILS: request', { hasId: true });

  const { status, data } = await getJson(url.toString());
  if (status < 200 || status >= 300) {
    debug('ADDRESS PLACE DETAILS: HTTP error', { status });
    throw new Error('Place details fetch failed');
  }

  if (!data || data.status !== 'OK') {
    debug('ADDRESS PLACE DETAILS: Google status', {
      status: data?.status,
      error: data?.error_message,
    });
    throw new Error('Place details fetch failed');
  }

  const result = data.result || {};
  const components = result.address_components || [];
  const location = result.geometry?.location || {};

  const houseNumber = normalizeComponentValue(components, 'street_number');
  const street = normalizeComponentValue(components, 'route');
  const city =
    normalizeComponentValue(components, 'locality') ||
    normalizeComponentValue(components, 'administrative_area_level_2');
  const state = normalizeComponentValue(components, 'administrative_area_level_1');
  const postalCode = normalizeComponentValue(components, 'postal_code');
  const lga = normalizeComponentValue(components, 'administrative_area_level_2');
  const country = normalizeComponentValue(components, 'country');

  const address = {
    houseNumber,
    street,
    city,
    state,
    postalCode,
    lga,
    country: country || 'NG',
    landmark: null,
    formattedAddress: result.formatted_address || null,
    placeId: cleaned,
    lat: typeof location.lat === 'number' ? location.lat : null,
    lng: typeof location.lng === 'number' ? location.lng : null,
  };

  debug('ADDRESS PLACE DETAILS: success', {
    hasStreet: !!street,
    hasCity: !!city,
  });

  return address;
}

module.exports = {
  fetchAddressSuggestions,
  fetchPlaceDetails,
};
