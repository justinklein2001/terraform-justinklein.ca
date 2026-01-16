export const handler = async (event) => {
  console.log("EVENT:", JSON.stringify(event));

  // Verify environment variables are passing through
  const bucket = process.env.KB_BUCKET_NAME;

  return {
    statusCode: 200,
    headers: { 
      "Content-Type": "application/json",
      // CORS headers are handled by API Gateway, but good to have here too
      "Access-Control-Allow-Origin": "*" 
    },
    body: JSON.stringify({ 
      message: "Hello from the Serverless Quiz API",
      bucket_connected: !!bucket,
      timestamp: new Date().toISOString()
    }),
  };
};