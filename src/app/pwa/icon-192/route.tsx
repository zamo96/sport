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
          background: "linear-gradient(180deg, #126A4A 0%, #11261D 100%)",
          color: "#FFF9F1",
          fontSize: 74,
          fontWeight: 800
        }}
      >
        TS
      </div>
    ),
    { width: 192, height: 192 }
  );
}

