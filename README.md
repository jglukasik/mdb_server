This runs the serverside portion of MadisonAR. It uses web.py and is truly just an HTTP wrapper for a database call, and serializing it to JSON.

Initially we planned to do something more complex with UDP streaming where we could keep glass as stupid as possible and let the server stream updates to the client. We decided to go with a simple GET with glass' latitude and longitude, at the expense of having glass do more thinking... (at least for the time being.)
