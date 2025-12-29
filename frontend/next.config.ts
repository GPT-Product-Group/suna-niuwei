import type { NextConfig } from 'next';

// Dynamically determine backend URL based on Vercel environment
const getBackendUrl = (): string => {
  // If explicitly set via Vercel dashboard/env, use that (highest priority)
  const explicitUrl = process.env.NEXT_PUBLIC_BACKEND_URL;
  if (explicitUrl && explicitUrl.trim() !== '') {
    return explicitUrl;
  }
  
  // Vercel environment detection
  const vercelEnv = process.env.VERCEL_ENV; // 'production', 'preview', or 'development'
  const gitRef = process.env.VERCEL_GIT_COMMIT_REF || ''; // Branch name
  
  // Production environment
  if (vercelEnv === 'production') {
    return 'https://api.kortix.com/v1';
  }
  
  // Preview deployments (non-main branches)
  if (vercelEnv === 'preview' && gitRef && gitRef !== 'main') {
    // Sanitize branch name for URL
    const sanitizedBranch = gitRef
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
    return `https://${sanitizedBranch}.api-staging.suna.so/v1`;
  }
  
  // Main branch / staging (default)
  return 'https://staging-api.suna.so/v1';
};

const nextConfig = (): NextConfig => ({
  output: (process.env.NEXT_OUTPUT as 'standalone') || undefined,
  
  // Set environment variables
  env: {
    NEXT_PUBLIC_BACKEND_URL: getBackendUrl(),
  },
  
  // Webpack configuration to make Konva work with Next.js
  webpack: (config) => {
    config.externals = [...config.externals, { canvas: 'canvas' }]; // required to make Konva & react-konva work
    return config;
  },
  
  // Performance optimizations
  experimental: {
    // Optimize package imports for faster builds and smaller bundles
    optimizePackageImports: [
      'lucide-react',
      'framer-motion',
      '@radix-ui/react-icons',
      'recharts',
      'date-fns',
      '@tanstack/react-query',
      'react-icons',
    ],
  },
  
  // Enable compression
  compress: true,
  
  // Optimize images
  images: {
    formats: ['image/avif', 'image/webp'],
    deviceSizes: [640, 750, 828, 1080, 1200, 1920],
    imageSizes: [16, 32, 48, 64, 96, 128, 256],
    qualities: [75, 100],
  },
  
  async rewrites() {
    // Backend URL for reverse proxy:
    // - In Docker: use internal network URL (backend:8000)
    // - In development: use localhost:8000
    // - In production: this rewrite won't be used if NEXT_PUBLIC_BACKEND_URL is set to the actual API URL
    const internalBackendUrl = process.env.INTERNAL_BACKEND_URL || 'http://backend:8000';

    return [
      // Proxy API calls to backend (allows same-origin requests from browser)
      // This enables the frontend to make API calls without CORS issues
      {
        source: '/api/v1/:path*',
        destination: `${internalBackendUrl}/v1/:path*`,
      },
      {
        source: '/ingest/static/:path*',
        destination: 'https://eu-assets.i.posthog.com/static/:path*',
      },
      {
        source: '/ingest/:path*',
        destination: 'https://eu.i.posthog.com/:path*',
      },
      {
        source: '/ingest/flags',
        destination: 'https://eu.i.posthog.com/flags',
      },
    ];
  },
  
  // HTTP headers for caching and performance
  async headers() {
    return [
      {
        source: '/fonts/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      {
        source: '/:path*.woff2',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
    ];
  },
  
  skipTrailingSlashRedirect: true,
});

export default nextConfig;
