require 'uri'
require 'cgi'

require 'job_board_registrar'

describe JobBoardRegistrar do
  let :image_metadata_tarball do
    'somedir/metadata.tar.bz2'
  end

  subject do
    described_class.new(image_metadata_tarball)
  end

  before :each do
    subject.send(:logger).level = Logger::FATAL
  end

  it 'constructs an image extraction command' do
    expect(subject.send(:image_metadata_extract_command)).to eq(
      %w(tar -C somedir -xjvf "somedir/metadata.tar.bz2")
    )
  end

  context 'without a metadata tarball' do
    it 'aborts with exit 1' do
      inst = described_class.new(nil)
      inst.send(:logger).level = Logger::FATAL
      expect(inst.register!).to eq(1)
    end
  end

  context 'without a JOB_BOARD_IMAGES_URL' do
    it 'aborts with exit 1' do
      ENV['JOB_BOARD_IMAGES_URL'] = nil
      expect(subject.register!).to eq(1)
    end
  end

  context 'without an IMAGE_NAME' do
    it 'aborts with exit 1' do
      ENV['IMAGE_NAME'] = nil
      expect(subject.register!).to eq(1)
    end
  end

  context 'with a nonexistent metadata tarball' do
    before do
      ENV['IMAGE_NAME'] = 'foo'
      ENV['JOB_BOARD_IMAGES_URL'] = 'flah'
      allow(subject).to receive(:image_metadata_tarball_exists?)
        .and_return(false)
    end

    it 'aborts with exit 1' do
      expect(subject.register!).to eq(1)
    end
  end

  context 'when failing to extract the metadata tarball' do
    before do
      ENV['IMAGE_NAME'] = 'foo'
      ENV['JOB_BOARD_IMAGES_URL'] = 'flah'
      allow(subject).to receive(:image_metadata_tarball_exists?)
        .and_return(true)
      allow(subject).to receive(:extract_image_metadata_tarball)
        .and_return(false)
    end

    it 'aborts with exit 1' do
      expect(subject.register!).to eq(1)
    end
  end

  context 'when failing to make the registration request' do
    before do
      allow(subject).to receive(:image_metadata_tarball_exists?)
        .and_return(true)
      allow(subject).to receive(:extract_image_metadata_tarball)
        .and_return(true)
      allow(subject).to receive(:load_image_metadata)
      allow(subject).to receive(:dump_relevant_env_vars)
      allow(subject).to receive(:make_request).and_return(false)
    end

    it 'aborts with exit 1' do
      expect(subject.register!).to eq(1)
    end
  end

  {
    dev: {
      env: {
        CURL_EXE: ':',
        IMAGE_NAME: 'travis-ci-sheeple-12345678',
        JOB_BOARD_IMAGES_URL: 'http://flim:flam@job-board.example.org/images',
        PACKER_TEMPLATES_BRANCH: 'master',
        PACKER_TEMPLATES_SHA: 'fafafaf',
        PACKER_BUILDER_TYPE: 'googlecompute',
        TRAVIS_COOKBOOKS_BRANCH: 'serious-experimentation-time',
        TRAVIS_COOKBOOKS_EDGE_BRANCH: 'master',
        TRAVIS_COOKBOOKS_SHA: 'fafafaf',
        dist: 'frosty',
        os: 'lintux'
      },
      expected: {
        infra: 'gce',
        name: 'travis-ci-sheeple-12345678',
        tags: {
        os: 'lintux',
        dist: 'frosty',
        group: 'dev'
      }
      }
    },
    edge: {
      env: {
        CURL_EXE: ':',
        IMAGE_NAME: 'travis-ci-foo-flah-99999999999',
        JOB_BOARD_IMAGES_URL: 'http://flim:flam@job-board.example.org/images',
        PACKER_TEMPLATES_BRANCH: 'master',
        PACKER_TEMPLATES_SHA: 'fafafaf',
        PACKER_BUILDER_TYPE: 'googlecompute',
        TRAVIS_COOKBOOKS_BRANCH: 'master',
        TRAVIS_COOKBOOKS_EDGE_BRANCH: 'master',
        TRAVIS_COOKBOOKS_SHA: 'fafafaf',
        dist: 'crusty',
        os: 'linnix'
      },
      expected: {
        infra: 'gce',
        name: 'travis-ci-foo-flah-99999999999',
        tags: {
        os: 'linnix',
        dist: 'crusty',
        group: 'edge'
      }
      }
    }
  }.each do |suite_name, config|
    context "with #{suite_name} config" do
      before :each do
        ENV.clear

        config[:env].each do |key, value|
          next unless key.to_s.upcase == key.to_s
          ENV[key.to_s] = value
        end

        allow(subject).to receive(:load_envdir).with('somedir/job-board-env')
        allow(subject).to receive(:image_metadata_tarball_exists?)
          .and_return(true)
        allow(subject).to receive(:image_metadata_envdir_isdir?)
          .and_return(true)
        allow(subject).to receive(:load_envdir).with('somedir/metadata/env')
        allow(subject).to receive(:extract_image_metadata_tarball)
          .and_return(true)
        allow(subject).to receive(:os).and_return(config[:env][:os])
        allow(subject).to receive(:dist).and_return(config[:env][:dist])
        subject.send(:logger).level = Logger::FATAL
      end

      it "registers an image for #{suite_name} config" do
        expect(subject).to receive(:make_request).once
        subject.register!
      end

      describe "#{suite_name} config job-board registration URL" do
        let :url do
          URI(subject.send(:request_command).last.delete("'"))
        end

        let :query do
          CGI.parse(url.query).tap do |q|
            q.each do |key, value|
              q[key] = value.first
            end
          end
        end

        let :tags do
          Hash[query['tags'].split(',').map { |s| s.split(':') }]
        end

        before :each do
          allow(subject).to receive(:make_request).and_return(true)
          subject.register!
        end

        it { expect(url).to_not be_nil }

        %w(name infra tags).each do |key|
          describe(key) { it { expect(query[key]).to_not be_nil } }
        end

        %w(name infra).each do |key|
          describe(key) do
            it { expect(query[key]).to eq(config[:expected][key.to_sym]) }
          end
        end

        %w(os group dist).each do |key|
          describe("#{key} tag") do
            it { expect(tags[key]).to eq(config[:expected][:tags][key.to_sym]) }
          end
        end
      end
    end
  end
end
