/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: "#11261D",
        sand: "#F4EFE6",
        clay: "#C96D42",
        court: "#126A4A",
        mint: "#CDE8D9",
        cream: "#FFF9F1",
        line: "#D8D2C7"
      },
      boxShadow: {
        card: "0 18px 45px rgba(17, 38, 29, 0.12)",
        glow: "0 12px 34px rgba(201, 109, 66, 0.24)"
      },
      backgroundImage: {
        court:
          "radial-gradient(circle at top, rgba(201, 109, 66, 0.18), transparent 38%), linear-gradient(180deg, #FFF9F1 0%, #F4EFE6 52%, #E5F3EC 100%)"
      }
    }
  },
  plugins: []
};

