from locust import HttpLocust, TaskSet
from wordpress_xmlrpc import WordPressPost, Client
from wordpress_xmlrpc.methods.posts import GetPosts, NewPost
import lorem

def index(l):
    l.client.get("/")
    wp = Client('http://local.rtdemo.in/xmlrpc.php', 'admin', 'admin')
    post = WordPressPost()
    post.title = lorem.sentence()
    post.content = lorem.paragraph()
    post.post_status = 'publish'
    post.terms_names = {
        'post_tag': ['test', 'firstpost'],
        'category': ['Introductions', 'Tests']
    }
    wp.call(NewPost(post))


class UserBehavior(TaskSet):
    tasks = {index: 2}

    def on_start(self):
        index(self)

class WebsiteUser(HttpLocust):
    task_set = UserBehavior
    min_wait = 5000
    max_wait = 9000
