// This Node.JS script small script will fetch a specific Meetup.com group and
// do a desired task for every new member.
// For example it will Follow them on Twitter, Added on Linkedin, etc

// The first implementation will add them to a list on Twitter

var twitter = require('twitter');

// **** remove and put it config file, and read from it
var meetup_api_key = "";
var meetup_uri_name = "DublinMUG";

// gianpaj
var twit = new twitter({
    consumer_key: '',
    consumer_secret: '',
    access_token_key: '',
    access_token_secret: ''
});

var meetup = require('meetup-api')(meetup_api_key);

meetup.getProfiles({'group_urlname': meetup_uri_name, 'order': 'joined', 'desc': true, 'page': 10, 'fields': 'other_services'}, function(err, result) {
    if (err) {
        console.log(err);
    }

  // console.log(events);
  result.results.forEach(function(member){
    // console.log(member.name, new Date(Number(member.created)));
    if (member.other_services.twitter !== undefined) {

        twit.get('/statuses/user_timeline.json', {screen_name: member.other_services.twitter.identifier.slice(1), count: 1}, function(data) {
            // console.log(util.inspect(data[0]));
            if (data[0] !== undefined) {
                console.log(member.other_services.twitter.identifier);
                console.log(data[0].text);
                console.log('------');
            }
        });
    }
    // console.log(member.other_services.twitter.identifier);
  });
});