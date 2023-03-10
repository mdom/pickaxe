package App::pickaxe::DiffPager;
use Mojo::Base 'App::pickaxe::UI::Pager', -signatures;
use App::pickaxe::Format;

has [qw(old_page new_page config)];

sub statusbar ($self) {
    my $fmt = App::pickaxe::Format->new(
        format     => $self->config->diff_pager_format,
        identifier => {
            t => sub { $_[0]->new_page->title },
            A => sub { $_[0]->new_page->author->{name} },
            a => sub { $_[0]->old_page->author->{name} },
            V => sub { $_[0]->new_page->version },
            v => sub { $_[0]->old_page->version },
        }
    );
    return $fmt->printf($self);
}

1;
