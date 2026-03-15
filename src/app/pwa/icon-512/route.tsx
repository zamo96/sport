import { ImageResponse } from "next/og";

export async function GET() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(180deg, #C96D42 0%, #126A4A 100%)",
          color: "#FFF9F1",
          fontSize: 190,
          fontWeight: 800
        }}
      >
        TS
      </div>
    ),
    { width: 512, height: 512 }
  );
}

