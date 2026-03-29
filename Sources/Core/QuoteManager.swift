import Foundation

struct QuoteManager: Sendable {
    private let quotes: [Quote]

    init() {
        // 尝试从 bundle 加载 Quotes.json
        if let url = Bundle.main.url(forResource: "Quotes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([Quote].self, from: data) {
            quotes = loaded
        } else {
            quotes = QuoteManager.builtInQuotes
        }
    }

    func random() -> Quote {
        quotes.randomElement() ?? Quote(en: "Take a break.", zh: "休息一下。", author: nil)
    }

    private static let builtInQuotes: [Quote] = [
        Quote(
            en: "It is not enough to be busy. So are the ants. The question is: What are we busy about?",
            zh: "忙碌是不够的，蚂蚁也很忙。问题是：我们在忙什么？",
            author: "Henry David Thoreau"
        ),
        Quote(
            en: "Take rest; a field that has rested gives a bountiful crop.",
            zh: "休息吧；休耕的土地才能长出丰盛的庄稼。",
            author: "Ovid"
        ),
        Quote(
            en: "The bow kept forever taut will break.",
            zh: "弓弦长绷必断。",
            author: "Phaedrus"
        ),
        Quote(
            en: "Nature does not hurry, yet everything is accomplished.",
            zh: "自然从不匆忙，却万事皆成。",
            author: "Lao Tzu"
        ),
        Quote(
            en: "Almost everything will work again if you unplug it for a few minutes, including you.",
            zh: "几乎所有东西拔掉电源几分钟后都能恢复运转，包括你自己。",
            author: "Anne Lamott"
        ),
        Quote(en: "Beware the barrenness of a busy life.", zh: "警惕忙碌生活的贫瘠。", author: "Socrates"),
        Quote(en: "Besides the noble art of getting things done, there is the noble art of leaving things undone.", zh: "除了把事做成的高贵艺术，还有一门高贵的艺术叫留白。", author: "Lin Yutang"),
        Quote(en: "All of humanity's problems stem from man's inability to sit quietly in a room alone.", zh: "人类所有的问题，都源于无法安静地独坐在一个房间里。", author: "Blaise Pascal"),
        Quote(en: "Rest belongs to the work as the eyelids to the eyes.", zh: "休息之于工作，如眼皮之于眼睛。", author: "Rabindranath Tagore"),
        Quote(en: "How we spend our days is how we spend our lives.", zh: "我们如何度过每一天，就是如何度过一生。", author: "Annie Dillard"),
        Quote(en: "I always stopped when I knew what was going to happen next.", zh: "我总是在知道下一步要做什么时收手。", author: "Ernest Hemingway"),
        Quote(en: "To the mind that is still, the whole universe surrenders.", zh: "心静则万物归降。", author: "Lao Tzu"),
        Quote(en: "Silence is the language of God, all else is poor translation.", zh: "沉默是神的语言，其余的都是拙劣的翻译。", author: "Rumi"),
        Quote(en: "The time to relax is when you don't have time for it.", zh: "最需要放松的时候，往往是你觉得没时间放松的时候。", author: "Sydney J. Harris"),
        Quote(en: "There is more to life than increasing its speed.", zh: "生活不只是加速。", author: "Mahatma Gandhi"),
        Quote(en: "The ability to be in the present moment is a major component of mental wellness.", zh: "活在当下的能力，是心理健康的重要组成部分。", author: "Abraham Maslow"),
        Quote(en: "A good rest is half the work.", zh: "好好休息，是工作的一半。", author: "Yugoslav Proverb"),
        Quote(en: "When you arise in the morning, think of what a precious privilege it is to be alive.", zh: "清晨醒来，想想能活着是多大的福气。", author: "Marcus Aurelius"),
        Quote(en: "Time alone is ours; everything else belongs to others.", zh: "唯有时间是我们自己的，其余一切皆为外物。", author: "Seneca"),
        Quote(en: "You must live in the present, launch yourself on every wave, find eternity in each moment.", zh: "你必须活在当下，乘着每一个浪头，在每个瞬间里找到永恒。", author: "Henry David Thoreau"),
        Quote(en: "Flow with whatever may happen and let your mind be free.", zh: "顺应一切变化，让心灵自由。", author: "Zhuangzi"),
        Quote(en: "In every walk with nature, one receives far more than he seeks.", zh: "每一次走入自然，所获都远超所求。", author: "John Muir"),
        Quote(en: "You cannot find peace by avoiding life.", zh: "逃避生活，找不到宁静。", author: "Virginia Woolf"),
        Quote(en: "I loafe and invite my soul.", zh: "我悠然漫步，邀请灵魂同行。", author: "Walt Whitman"),
        Quote(en: "Make the best use of what is in your power, and take the rest as it happens.", zh: "善用你能掌控的，其余的顺其自然。", author: "Epictetus"),
        Quote(en: "Attention is the rarest and purest form of generosity.", zh: "专注是最罕见、最纯粹的慷慨。", author: "Simone Weil"),
        Quote(en: "Realize deeply that the present moment is all you ever have.", zh: "深刻地意识到：当下，是你唯一真正拥有的。", author: "Eckhart Tolle"),
        Quote(en: "Know when to stop, and you will find stillness.", zh: "知止而后有定，定而后能静。", author: "The Great Learning"),
        Quote(en: "The soul that sees beauty may sometimes walk alone.", zh: "能看见美的灵魂，有时需要独自行走。", author: "Johann Wolfgang von Goethe"),
        Quote(en: "The time you enjoy wasting is not wasted time.", zh: "你享受地虚度的时光，不是虚度。", author: "Bertrand Russell"),
    ]
}
