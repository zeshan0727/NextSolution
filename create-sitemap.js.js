const fs = require('fs');

// Read movies from generate-pages.js
let movies = [];
try {
    // Try to read the movies array from generate-pages.js
    const generatePagesContent = fs.readFileSync('generate-pages.js', 'utf8');
    
    // Extract movies array using regex (simple method)
    const moviesMatch = generatePagesContent.match(/const movies = (\[[\s\S]*?\]);/);
    
    if (moviesMatch) {
        // Safe eval to get movies array
        movies = eval(moviesMatch[1]);
    } else {
        console.log("⚠️ Could not extract movies array, using empty array");
    }
} catch (error) {
    console.log("⚠️ Error reading movies:", error.message);
    movies = [];
}

// Get current date
const today = new Date().toISOString().split('T')[0];

// Create sitemap
let sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>https://zeshan0727.github.io/NextSolution/</loc>
        <lastmod>${today}</lastmod>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>https://zeshan0727.github.io/NextSolution/movies.html</loc>
        <lastmod>${today}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.9</priority>
    </url>`;

// Add each movie page to sitemap
movies.forEach(movie => {
    const slug = movie.title.toLowerCase()
        .replace(/[^\w\s-]/g, '')
        .replace(/\s+/g, '-')
        .replace(/--+/g, '-');
    
    sitemap += `
    <url>
        <loc>https://zeshan0727.github.io/NextSolution/movies/${slug}.html</loc>
        <lastmod>${today}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>`;
});

sitemap += '\n</urlset>';

// Save sitemap
fs.writeFileSync('sitemap.xml', sitemap);
console.log('✅ Generated sitemap.xml with', movies.length, 'movie URLs');

// Also create robots.txt
const robots = `User-agent: *
Allow: /
Sitemap: https://zeshan0727.github.io/NextSolution/sitemap.xml

# Crawl-delay: 10
# Disallow: /private/
`;

fs.writeFileSync('robots.txt', robots);
console.log('✅ Generated robots.txt');